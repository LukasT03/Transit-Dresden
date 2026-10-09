//
//  GoViewModel.swift
//  Transit Dresden
//

import Foundation
import CoreLocation
import Observation

/// Zustand der Los-Ansicht: Ziel, Standort und die Verbindungen, die der RoutePlanner anbietet.
/// Fußweg zur Haltestelle und die Wahl der Starthaltestelle übernimmt die VVO-Routenplanung,
/// weil als Start der Standort übergeben wird.
@MainActor @Observable
final class GoViewModel {
    enum Phase: Equatable {
        case idle
        case locating
        case planning
        case loaded
        case failed(String)
    }

    private(set) var destination: ConnectionStop?
    private(set) var phase: Phase = .idle
    /// Verbindungen zur Wahl, chronologisch nach Losgehzeit
    private(set) var routes: [Route] = []
    var selectedIndex = 0
    /// Ein- und Ausstiege, an denen mehrere Steige bedient werden; nur dort zeigt der Ablauf den Steig.
    /// Steht schon fest, wenn die Verbindungen erscheinen, damit der Ablauf nicht nachträglich wächst.
    private(set) var platformStops: Set<RegularStop> = []
    /// IDs der Haltestellen, an denen man gerade steht. Steht man dort nur an einem anderen Steig als dem
    /// der ersten Fahrt, geht es im Ablauf "Zu Steig 3" statt "Zur Haltestelle".
    private(set) var nearbyStops: Set<String> = []

    @ObservationIgnored private var serviceSession: CLServiceSession?
    /// Letzte Position der laufenden Ortung, siehe trackLocation()
    @ObservationIgnored private var lastLocation: CLLocation?
    /// Vorschau-Modus: zeigt feste Beispieldaten und plant nicht über das Netz
    @ObservationIgnored private var isPreview = false

    var selectedRoute: Route? {
        routes.indices.contains(selectedIndex) ? routes[selectedIndex] : nil
    }

    func select(_ destination: ConnectionStop) {
        RecentDestinations.add(destination)
        self.destination = destination
        routes = []
        selectedIndex = 0
        phase = .idle
    }

    /// Plant ab dem aktuellen Standort. Bei `silent` bleiben bisherige Ergebnisse sichtbar
    /// und Fehler werden ignoriert, solange schon Verbindungen angezeigt werden.
    func plan(silent: Bool = false) async {
        guard let destination, !isPreview else { return }
        let showProgress = !silent || routes.isEmpty

        if showProgress {
            phase = .locating
        }
        // Ziel schon während der Ortung auflösen; bei Adressen ist das eine eigene Anfrage
        async let destinationID = destination.getDestinationString()
        guard let location = await currentLocation() else {
            fail("Dein Standort konnte nicht bestimmt werden. Ist die Ortung für Transit erlaubt?", silent: silent)
            return
        }

        if showProgress {
            phase = .planning
        }
        let origin = ConnectionStop(
            displayName: "Standort",
            location: StopCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        )
        async let originID = origin.getDestinationString()
        let (from, to) = await (originID, destinationID)

        guard from != "0", to != "0" else {
            fail("Start oder Ziel konnte bei der Fahrplanauskunft nicht ermittelt werden. Prüfe deine Internetverbindung.", silent: silent)
            return
        }
        guard from != to else {
            fail("Du bist schon am Ziel.", silent: silent)
            return
        }

        do {
            var planner = try await RoutePlanner(from: from, to: to, location: location)
            // Beim ersten Laden gleich zeigen und erst danach nachladen, damit die Ansicht nicht darauf wartet.
            // Beim Aktualisieren erst alles zusammen, sonst schrumpfte die Auswahl jedes Mal kurz.
            var shownAt: ContinuousClock.Instant?
            if !silent, !planner.options().isEmpty {
                guard await show(planner, for: destination, keepSelection: false) else { return }
                shownAt = .now
            }
            await planner.loadMore()
            // Nachgeladene erst, wenn die Ansicht steht: Kämen sie mit der unteren Leiste, wirkte es zufällig.
            // Gezählt ab dem Einblenden, ein langsames Nachladen wartet also nicht noch zusätzlich.
            if let shownAt {
                try? await Task.sleep(until: shownAt + .seconds(1))
            }
            // die neuen gehen später los und kommen hinten dazu, die gewählte bleibt
            await show(planner, for: destination, keepSelection: true)
        } catch {
            if !Task.isCancelled {
                fail("Die Verbindungen konnten nicht geladen werden.", silent: silent)
            }
        }
    }

    /// Zeigt die Verbindungen zur Wahl, sobald die Steige ihrer Haltestellen geklärt sind.
    /// false, wenn inzwischen ein anderes Ziel gewählt wurde.
    @discardableResult
    private func show(_ planner: RoutePlanner, for destination: ConnectionStop, keepSelection: Bool) async -> Bool {
        let options = planner.options()
        let platformStops = await TripService.stopsWithSeveralPlatforms(on: options)
        guard self.destination == destination else { return false }
        self.platformStops = platformStops
        nearbyStops = planner.nearbyStops

        let previousKey = keepSelection ? selectedRoute.map(Self.key) : nil
        routes = options
        if let previousKey, let index = routes.firstIndex(where: { Self.key($0) == previousKey }) {
            selectedIndex = index
        } else {
            selectedIndex = RoutePlanner.bestIndex(in: routes) ?? 0
        }
        phase = routes.isEmpty ? .failed("Keine erreichbare Verbindung gefunden.") : .loaded
        return true
    }

    private func fail(_ message: String, silent: Bool) {
        if !silent || routes.isEmpty {
            routes = []
            phase = .failed(message)
        }
    }

    /// Stabile Kennung einer Verbindung über Linie und Plan-Abfahrt der ersten Fahrt,
    /// damit die Auswahl bei Echtzeit-Änderungen erhalten bleibt
    private static func key(_ route: Route) -> String {
        guard let ride = route.firstRide else {
            return "walk|\(route.arrivalTime?.timeIntervalSince1970 ?? 0)"
        }
        return "\(ride.Mot.Name ?? "")|\(ride.RegularStops?.first?.DepartureTime ?? "")"
    }

    // MARK: - Standort

    /// Hält die Ortung aktiv, solange die Los-Ansicht zu sehen ist. So steht der Standort beim Tippen auf ein Ziel
    /// meist schon fest, statt dass die Ortung erst dann startet.
    func trackLocation() async {
        guard !isPreview else { return }
        startServiceSession()
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    lastLocation = location
                }
            }
        } catch {
            print("GoViewModel location error: \(error)")
        }
    }

    /// Eine frische, genaue Position der laufenden Ortung sofort, sonst die erste brauchbare; höchstens 30 s warten
    private func currentLocation() async -> CLLocation? {
        if let lastLocation, lastLocation.horizontalAccuracy <= 100, lastLocation.timestamp.timeIntervalSinceNow > -30 {
            return lastLocation
        }
        startServiceSession()
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { await Self.firstUsableLocation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return nil
            }
            let location = await group.next() ?? nil
            group.cancelAll()
            return location
        }
    }

    private func startServiceSession() {
        if serviceSession == nil {
            // Fragt bei Bedarf nach der Berechtigung und hält die Ortung aktiv
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }
    }

    /// Erste Position mit brauchbarer Genauigkeit, nach 5 Sekunden auch eine ungenauere
    private nonisolated static func firstUsableLocation() async -> CLLocation? {
        let start = Date.now
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    return nil
                }
                guard let location = update.location else { continue }
                if location.horizontalAccuracy <= 100 || Date.now.timeIntervalSince(start) > 5 {
                    return location
                }
            }
        } catch {
            print("GoViewModel location error: \(error)")
        }
        return nil
    }
}

#if DEBUG
extension GoViewModel {
    /// Beispielverbindungen aus trip.json für Xcode-Vorschauen.
    /// Die Zeiten werden so verschoben, dass die erste Verbindung in 5 Minuten startet.
    static var preview: GoViewModel {
        let model = GoViewModel()
        model.isPreview = true
        model.destination = ConnectionStop(displayName: "Hauptbahnhof")

        let routes = tripTmp.Routes
        let earliest = routes.compactMap(\.leaveTime).min() ?? .now
        let offset = Date.now.addingTimeInterval(5 * 60).timeIntervalSince(earliest)
        model.routes = RoutePlanner.chronological(routes.map { shifted($0, by: offset) })
        model.selectedIndex = RoutePlanner.bestIndex(in: model.routes) ?? 0
        // ohne Abfrage überall den Steig zeigen
        model.platformStops = Set(model.routes.flatMap(\.boardingAndAlightingStops))
        model.phase = .loaded
        return model
    }

    private static func shifted(_ route: Route, by offset: TimeInterval) -> Route {
        var route = route
        for partialIndex in route.PartialRoutes.indices {
            guard let stops = route.PartialRoutes[partialIndex].RegularStops else { continue }
            route.PartialRoutes[partialIndex].RegularStops = stops.map { stop in
                var stop = stop
                stop.ArrivalTime = shifted(stop.ArrivalTime, by: offset) ?? stop.ArrivalTime
                stop.DepartureTime = shifted(stop.DepartureTime, by: offset) ?? stop.DepartureTime
                stop.ArrivalRealTime = shifted(stop.ArrivalRealTime, by: offset)
                stop.DepartureRealTime = shifted(stop.DepartureRealTime, by: offset)
                return stop
            }
        }
        return route
    }

    /// Verschiebt einen Zeitstempel im VVO-Format "/Date(<ms>-0000)/"
    private static func shifted(_ time: String?, by offset: TimeInterval) -> String? {
        guard let time, let date = DateParser.extractTimestamp(time: time) else { return time }
        return "/Date(\(Int64((date.timeIntervalSince1970 + offset) * 1000))-0000)/"
    }
}
#endif
