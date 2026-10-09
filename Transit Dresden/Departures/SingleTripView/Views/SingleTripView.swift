//
//  SingleTripView.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 21.04.23.
//

import SwiftUI

struct SingleTripView: View {
    @State var stopSequence: [StopSequenceItem] = []
    @State private var isLoaded = false
    @State private var searchText = ""
    var stop: Stop
    var stopEvent: StopEvent

    var body: some View {

        Group {
            if isLoaded {
                List {
                    if stopEvent.hasInfos() {
                        HStack {
                            ZStack {
                                NavigationLink {
                                    DepartureInfoView(stopEvent: stopEvent)
                                } label: {
                                    EmptyView()
                                }
                                .opacity(0.0)
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("Aktuelle Meldungen")
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Zeigt eine Liste der aktuellen Meldungen zu dieser Linie an")
                            .accessibilityAddTraits(.isButton)
                        }
                        .listRowBackground(Color.orange)
                    }
                    Section {
                        ForEach(searchResults, id: \.self) { stopSequenceItem in
                            ZStack {
                                NavigationLink {
                                    DepartureView(stop: stopSequenceItem.getStop() ?? stop)
                                } label: {
                                    EmptyView()
                                }
                                .opacity(0.0)
                                .buttonStyle(.plain)

                                SingleTripRow(stopSequenceItem: stopSequenceItem)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Zeige Haltestelle \(stopSequenceItem.getStop()?.name ?? "")")
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }

            } else {
                List {
                    Section {
                        ForEach(0..<12, id: \.self) { _ in
                                SingleTripRowSkeleton()
                            }
                        }
                    }
                }

        }
        .refreshable {
            await getSingleTrip()
        }
        .navigationTitle("\(stopEvent.getIcon()) \(stopEvent.getName())")
        .task(id: stopEvent.transportation.properties.globalId, priority: .userInitiated) {
            await getSingleTrip()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled {
                        await getSingleTrip()
                    }
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }

    var searchResults: [StopSequenceItem] {
        if searchText.isEmpty {
            return stopSequence
        } else {
            return stopSequence.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
    }

    func getSingleTrip() async {
        let url = URL(string: "https://efa.vvo-online.de/std3/trias/XML_TRIPSTOPTIMES_REQUEST")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"

        let date = getISO8601Date(dateString: stopEvent.departureTimePlanned)

        request.httpBody = createDepartureRequestSingle(stopId: stop.gid, line: stopEvent.transportation.id, tripCode: stopEvent.transportation.properties.tripCode ?? 0, date: getDateStampURL(date: date), time: getTimeStampURL(date: date)).data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (content, _) = try await URLSession.shared.data(for: request)
            let stopSequenceContainer = try JSONDecoder().decode(StopSequenceContainer.self, from: content)
            let stopEvents = stopSequenceContainer.leg.stopSequence ?? []

            await MainActor.run {
                if stopEvents.count > 0 {
                    self.stopSequence = stopEvents
                }
                self.isLoaded = true
            }
        } catch {
            if !Task.isCancelled {
                print("SingleTrip error: \(error)")
                do {
                    try await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled {
                        await getSingleTrip()
                    }
                } catch {
                    // Task was cancelled during sleep
                    return
                }
            }
        }
    }

}
