//
//  GoView.swift
//  TransitDresden
//

import SwiftUI
import MapKit

/// Einfacher Weg zum Ziel: Ziel wählen, die App plant ab dem aktuellen Standort
struct GoView: View {
    @EnvironmentObject var favoriteStops: FavoriteStop
    @State private var model = GoViewModel()
    @State private var addressSearch = AddressSearch()
    @State private var searchText = ""
    @State private var recents: [ConnectionStop] = []

    var body: some View {
        NavigationStack {
            Group {
                if model.destination == nil {
                    destinationPicker
                } else {
                    GoResultView(model: model)
                }
            }
            .navigationDestination(for: Stop.self) { stop in
                DepartureView(stop: stop)
            }
        }
    }

    // MARK: - Ziel wählen

    private var destinationPicker: some View {
        List {
            if searchText.isEmpty {
                Section("Favoriten") {
                    if favoriteStopList.isEmpty {
                        Text("Markiere Haltestellen unter „Abfahrten“ per Wischgeste als Favorit, dann erscheinen sie hier.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(favoriteStopList) { stop in
                        destinationRow(ConnectionStop(displayName: stop.getFullName(), stop: stop)) {
                            StopRow(stop: stop)
                        }
                    }
                }
                if !recents.isEmpty {
                    Section("Zuletzt") {
                        ForEach(recents, id: \.self) { destination in
                            destinationRow(destination) {
                                Label(destination.displayName, systemImage: destination.stop == nil ? "mappin.and.ellipse" : "clock.arrow.circlepath")
                            }
                        }
                    }
                }
            } else {
                Section("Haltestellen") {
                    ForEach(matchingStops) { stop in
                        destinationRow(ConnectionStop(displayName: stop.getFullName(), stop: stop)) {
                            StopRow(stop: stop)
                        }
                    }
                }
                if !addressSearch.results.isEmpty {
                    Section("Adressen und Orte") {
                        ForEach(addressSearch.results, id: \.self) { completion in
                            Button {
                                Task {
                                    if let destination = await addressSearch.resolve(completion) {
                                        choose(destination)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(completion.title)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Wohin?")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Haltestelle oder Adresse")
        .onChange(of: searchText) {
            addressSearch.update(query: searchText)
        }
        .onAppear {
            recents = RecentDestinations.load()
        }
    }

    private var favoriteStopList: [Stop] {
        favoriteStops.favorites.compactMap { stopID in
            stops.first { $0.stopID == stopID }
        }
    }

    private var matchingStops: [Stop] {
        Array(stops.filter { $0.getFullName().localizedCaseInsensitiveContains(searchText) }.prefix(15))
    }

    private func destinationRow(_ destination: ConnectionStop, @ViewBuilder label: () -> some View) -> some View {
        Button {
            choose(destination)
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ destination: ConnectionStop) {
        searchText = ""
        model.select(destination)
    }
}

// MARK: - Ergebnis

private struct GoResultView: View {
    var model: GoViewModel

    var body: some View {
        content
            .navigationTitle(model.destination?.displayName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anderes Ziel", systemImage: "xmark") {
                        model.reset()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if model.isRefreshing {
                        ProgressView()
                    } else {
                        Button("Aktualisieren", systemImage: "arrow.clockwise") {
                            Task {
                                await model.plan(silent: true)
                            }
                        }
                    }
                }
            }
            .task(id: model.destination) {
                await model.plan()
                // Echtzeitdaten und Standort regelmäßig aktualisieren
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if Task.isCancelled {
                        break
                    }
                    await model.plan(silent: true)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .locating:
            ProgressView("Standort wird bestimmt …")
        case .planning:
            ProgressView("Verbindung wird gesucht …")
        case .failed(let message):
            ContentUnavailableView {
                Label("Keine Verbindung", systemImage: "tram")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") {
                    Task {
                        await model.plan()
                    }
                }
            }
        case .loaded:
            if let route = model.selectedRoute {
                List {
                    Section {
                        RouteSummary(route: route, isBest: model.selectedIndex == model.bestIndex)
                    }
                    Section("Ablauf") {
                        RouteLegs(vm: TripSectionViewModel(route: route))
                    }
                    Section {
                        alternatives
                    }
                }
            }
        }
    }

    private var alternatives: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    model.selectedIndex -= 1
                } label: {
                    Label("Früher", systemImage: "chevron.left")
                }
                .disabled(model.selectedIndex == 0)

                Spacer()

                Text("\(model.selectedIndex + 1) von \(model.routes.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    if model.selectedIndex + 1 < model.routes.count {
                        model.selectedIndex += 1
                    } else {
                        Task {
                            await model.loadLater()
                        }
                    }
                } label: {
                    if model.isLoadingLater {
                        ProgressView()
                    } else {
                        HStack(spacing: 4) {
                            Text("Später")
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
            if let bestIndex = model.bestIndex, bestIndex != model.selectedIndex {
                Button("Zur schnellsten Verbindung") {
                    model.selectedIndex = bestIndex
                }
                .font(.footnote)
            }
        }
        .buttonStyle(.borderless)
    }
}

/// Kopf der gewählten Verbindung mit Countdown bis zum Losgehen
private struct RouteSummary: View {
    let route: Route
    let isBest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isBest {
                Text("Schnellste Ankunft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(countdown(at: context.date))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
            }
            Text(details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(rideDescription)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func countdown(at date: Date) -> String {
        guard let leaveTime = route.leaveTime else { return "–" }
        let minutes = Int(leaveTime.timeIntervalSince(date) / 60)
        return minutes <= 0 ? "Jetzt los" : "Los in \(minutes) Min"
    }

    private var details: String {
        var parts: [String] = []
        if let arrival = route.arrivalTime {
            parts.append("Ankunft \(arrival.formatted(date: .omitted, time: .shortened))")
            if let leaveTime = route.leaveTime {
                parts.append("\(Int(arrival.timeIntervalSince(leaveTime) / 60)) Min")
            }
        }
        if route.Interchanges > 0 {
            parts.append(route.Interchanges == 1 ? "1 Umstieg" : "\(route.Interchanges) Umstiege")
        }
        return parts.joined(separator: " · ")
    }

    private var rideDescription: String {
        guard let ride = route.firstRide else { return "Zu Fuß" }
        var text = ride.getName()
        if let stopName = ride.RegularStops?.first?.Name, let time = ride.getStartTimeString() {
            text += " · ab \(stopName) \(time)"
        }
        if let platform = ride.getFirstPlatform() {
            text += " · \(platform)"
        }
        return text
    }
}

#Preview {
    GoView()
        .environmentObject(FavoriteStop())
        .environmentObject(LocationManager())
        .environmentObject(StopManager())
}
