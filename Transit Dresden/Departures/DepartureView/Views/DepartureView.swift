//
//  DepartureView.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 18.04.23.
//

import SwiftUI

struct DepartureView: View {
    var stop: Stop
    @EnvironmentObject var favoriteStops: FavoriteStop
    @State var stopEvents: [StopEvent] = []
    @State private var searchText = ""
    @State private var isLoaded = false
    @State private var dateTime = Date.now
    @StateObject var departureFilter = DepartureFilter()

    var body: some View {
        Group {
            if isLoaded {
                VStack {
                    Form {
                        Section {
                            DisclosureGroup("Verkehrsmittel") {
                                DepartureDisclosureSection()
                            }
                            HStack {
                                DatePicker(selection: $dateTime, in: Date()...) {
                                    Text("Zeit").accessibilityHint("Bei Bedarf hier gewünschten Zeitpunkt einstellen")
                                }

                                Button {
                                    dateTime = Date.now
                                } label: {
                                    Text("Jetzt")
                                        .accessibilityHint("Auf aktuellen Zeitpunkt zurücksetzen")
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                        Section {
                            // speed-up: don't use the getter
                            // no utc conversion needed for comparison
                                List(searchResults.sorted { ($0.departureTimeEstimated ?? $0.departureTimePlanned) < ($1.departureTimeEstimated ?? $1.departureTimePlanned) }, id: \.self) { stopEvent in
                                    ZStack {
                                        NavigationLink {
                                            SingleTripView(stop: stop, stopEvent: stopEvent)
                                        } label: {
                                            EmptyView()
                                        }
                                        .opacity(0.0)
                                        .buttonStyle(.plain)

                                        DepartureRow(stopEvent: stopEvent)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("Zeige \(stopEvent.hasInfos() ? "Meldungen & " : "")nächste Haltestellen dieser Linie")
                            }
                           
                        }
                        Section {
                            Button {
                                Task {
                                    await getDeparture(true)
                                }
                            } label: {
                                Text("Spätere Abfahrten laden")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // Skeleton
                Form {
                    Section {
                        DisclosureGroup("Verkehrsmittel") {
                            DepartureDisclosureSection()
                        }

                        HStack {
                            DatePicker("Zeit", selection: $dateTime)

                            Button {
                                dateTime = Date.now
                            } label: {
                                Text("Jetzt")
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                    .disabled(true)
                    .accessibilityHint("Warte auf Daten")
                    Section {
                        List(0..<9, id: \.self) { _ in
                            DepartureRowSkeleton()
                        }
                    }
                }
            }
        }
        .refreshable {
            if dateTime < Date.now {
                dateTime = Date.now
            }
            await getDeparture()
        }
        .navigationTitle(Text("🚏 \(stop.name)").accessibilityLabel("Haltestelle \(stop.name)"))
        .toolbar {
            Button {
                if favoriteStops.isFavorite(stopID: stop.stopID) {
                    favoriteStops.remove(stopID: stop.stopID)
                } else {
                    favoriteStops.add(stopID: stop.stopID)
                }
            } label: {
                if favoriteStops.isFavorite(stopID: stop.stopID) {
                    Label("Als Favorit entfernen", systemImage: "star.fill")
                } else {
                    Label("Als Favorit hinzufügen", systemImage: "star")
                }
            }
        }

        .task(id: stop.id, priority: .userInitiated) {
            await getDeparture()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled {
                        await getDeparture()
                    }
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onChange(of: dateTime) {
            Task {
                await getDeparture()
            }
        }
        .environmentObject(departureFilter)
    }

    var searchResults: [StopEvent] {
        var stopEventsTmp = stopEvents
        stopEventsTmp = stopEventsTmp.filter {
            (departureFilter.tram && $0.transportation.product.iconId == 4) ||
            (departureFilter.bus && $0.transportation.product.iconId == 3) ||
            (departureFilter.suburbanRailway && $0.transportation.product.iconId == 2) ||
            (departureFilter.train && $0.transportation.product.iconId == 6) ||
            (departureFilter.cableway && $0.transportation.product.iconId == 9) ||
            (departureFilter.ferry && $0.transportation.product.iconId == 10)
        }

        if searchText.isEmpty {
            return stopEventsTmp
        } else {
            return stopEventsTmp.filter {
                $0.getName().lowercased().contains(searchText.lowercased())
            }
        }
    }

    func getDeparture(_ showLater: Bool = false) async {
        var localDateTime = dateTime
        if localDateTime < Date.now {
            localDateTime = Date.now
        }
        
        if showLater {
            dateTime = dateTime + (5 * 60) // 5 minutes
        }

        let url = URL(string: "https://efa.vvo-online.de/std3/trias/XML_DM_REQUEST")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"

        request.httpBody = createDepartureRequest(stopId: stop.gid, itdDate: getDateStampURL(date: localDateTime), itdTime: getTimeStampURL(date: localDateTime)).data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (content, _) = try await URLSession.shared.data(for: request)
            let stopEventContainer = try JSONDecoder().decode(StopEventContainer.self, from: content)
            await MainActor.run {
                self.stopEvents = stopEventContainer.stopEvents ?? []
                self.isLoaded = true
            }

        } catch {
            if !Task.isCancelled {
                print("DepartureMonitor error: \(error)")
                do {
                    try await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        await getDeparture(showLater)
                    }
                } catch {
                    // Task was cancelled during sleep
                    return
                }
            }
        }
    }

}

 struct DepartureView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DepartureView(stop: stops[100])
        }
            .environmentObject(FavoriteStop())
    }
 }
