//
//  GoViewModel.swift
//  TransitDresden
//

import Foundation
import CoreLocation
import MapKit
import Observation

/// Plant vom aktuellen Standort zum gewählten Ziel und wählt die Verbindung mit der frühesten Ankunft.
/// Fußweg zur Haltestelle und die Wahl der Starthaltestelle übernimmt die VVO-Routenplanung,
/// weil als Start die GPS-Koordinate übergeben wird.
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
    /// Erreichbare Verbindungen, chronologisch nach Losgehzeit
    private(set) var routes: [Route] = []
    var selectedIndex = 0
    private(set) var isRefreshing = false
    private(set) var isLoadingLater = false

    @ObservationIgnored private var tripRequest: TripRequest?
    @ObservationIgnored private var sessionId: String?
    @ObservationIgnored private var serviceSession: CLServiceSession?

    var selectedRoute: Route? {
        routes.indices.contains(selectedIndex) ? routes[selectedIndex] : nil
    }

    var bestIndex: Int? {
        Self.bestIndex(in: routes)
    }

    func select(_ destination: ConnectionStop) {
        RecentDestinations.add(destination)
        self.destination = destination
        routes = []
        selectedIndex = 0
        phase = .idle
    }

    func reset() {
        destination = nil
        routes = []
        tripRequest = nil
        sessionId = nil
        phase = .idle
    }

    /// Plant ab dem aktuellen Standort. Bei `silent` bleiben bisherige Ergebnisse sichtbar
    /// und Fehler werden ignoriert, solange schon Verbindungen angezeigt werden.
    func plan(silent: Bool = false) async {
        guard let destination else { return }
        let showProgress = !silent || routes.isEmpty
        isRefreshing = true
        defer { isRefreshing = false }

        if showProgress {
            phase = .locating
        }
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
        async let destinationID = destination.getDestinationString()
        let (from, to) = await (originID, destinationID)

        guard from != "0", to != "0" else {
            fail("Start oder Ziel konnte bei der Fahrplanauskunft nicht ermittelt werden. Prüfe deine Internetverbindung.", silent: silent)
            return
        }
        guard from != to else {
            fail("Du bist schon am Ziel.", silent: silent)
            return
        }

        let request = TripRequest(
            time: Date.now.ISO8601Format(),
            isarrivaltime: false,
            origin: from,
            destination: to,
            standardSettings: TripService.standardSettings(from: DepartureFilter())
        )
        do {
            let trip = try await TripService.fetchTrips(request)
            // Ziel wurde während des Ladens geändert
            guard self.destination == destination else { return }
            tripRequest = request
            sessionId = trip.SessionId
            apply(trip.Routes, keepSelection: silent)
        } catch {
            if !Task.isCancelled {
                fail("Die Verbindungen konnten nicht geladen werden.", silent: silent)
            }
        }
    }

    /// Lädt spätere Verbindungen nach und springt zur nächsten
    func loadLater() async {
        guard var request = tripRequest, let sessionId, !isLoadingLater else { return }
        isLoadingLater = true
        defer { isLoadingLater = false }

        // Wie in der Verbindungssuche: jeweils eine Seite weiter, bezogen auf die letzte SessionId
        request.sessionId = sessionId
        request.numberprev = 0
        request.numbernext = 1

        guard let trip = try? await TripService.fetchTrips(request, isNext: true) else { return }
        self.sessionId = trip.SessionId

        let selectedKey = selectedRoute.map(Self.key)
        let known = Set(routes.map(Self.key))
        let added = Self.catchable(trip.Routes).filter { !known.contains(Self.key($0)) }
        routes = Self.chronological(routes + added)
        if let selectedKey, let index = routes.firstIndex(where: { Self.key($0) == selectedKey }) {
            selectedIndex = min(index + (added.isEmpty ? 0 : 1), routes.count - 1)
        }
    }

    // MARK: - Auswahl der Verbindung

    private func apply(_ newRoutes: [Route], keepSelection: Bool) {
        let previousKey = keepSelection ? selectedRoute.map(Self.key) : nil
        routes = Self.chronological(Self.catchable(newRoutes))

        if let previousKey, let index = routes.firstIndex(where: { Self.key($0) == previousKey }) {
            selectedIndex = index
        } else {
            selectedIndex = Self.bestIndex(in: routes) ?? 0
        }
        phase = routes.isEmpty ? .failed("Keine erreichbare Verbindung gefunden.") : .loaded
    }

    private func fail(_ message: String, silent: Bool) {
        if !silent || routes.isEmpty {
            routes = []
            phase = .failed(message)
        }
    }

    /// Nur Verbindungen, für die man noch rechtzeitig losgehen kann
    private static func catchable(_ routes: [Route]) -> [Route] {
        let limit = Date.now.addingTimeInterval(-30)
        return routes.filter { ($0.leaveTime ?? .distantPast) >= limit }
    }

    private static func chronological(_ routes: [Route]) -> [Route] {
        routes.sorted { ($0.leaveTime ?? .distantFuture) < ($1.leaveTime ?? .distantFuture) }
    }

    /// Früheste Ankunft, danach weniger Umstiege, danach späteres Losgehen (weniger Wartezeit)
    static func bestIndex(in routes: [Route]) -> Int? {
        routes.indices.min { a, b in
            let first = routes[a], second = routes[b]
            let firstArrival = first.arrivalTime ?? .distantFuture
            let secondArrival = second.arrivalTime ?? .distantFuture
            if firstArrival != secondArrival {
                return firstArrival < secondArrival
            }
            if first.Interchanges != second.Interchanges {
                return first.Interchanges < second.Interchanges
            }
            return (first.leaveTime ?? .distantPast) > (second.leaveTime ?? .distantPast)
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

    private func currentLocation() async -> CLLocation? {
        if serviceSession == nil {
            // Fragt bei Bedarf nach der Berechtigung und hält die Ortung aktiv
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }
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

extension Route {
    /// Zeitpunkt, zu dem man losgehen muss (erster Abschnitt mit Uhrzeit, meist der Fußweg)
    var leaveTime: Date? {
        PartialRoutes.lazy.compactMap { $0.getStartTime() }.first
    }

    var arrivalTime: Date? {
        PartialRoutes.reversed().lazy.compactMap { $0.getEndTime() }.first
    }

    /// Erster Abschnitt mit einem Verkehrsmittel (Fußwege und Wartezeiten haben keinen Liniennamen)
    var firstRide: PartialRoute? {
        PartialRoutes.first { $0.Mot.Name != nil && $0.RegularStops != nil }
    }
}

/// Zuletzt gewählte Ziele der Los-Ansicht
enum RecentDestinations {
    private static let key = "RecentDestinations"
    private static let limit = 5

    static func load() -> [ConnectionStop] {
        guard let data = UserDefaults.appGroup?.data(forKey: key),
              let destinations = try? JSONDecoder().decode([ConnectionStop].self, from: data) else {
            return []
        }
        return destinations
    }

    static func add(_ destination: ConnectionStop) {
        var destinations = load().filter { $0.displayName != destination.displayName }
        destinations.insert(destination, at: 0)
        if let data = try? JSONEncoder().encode(Array(destinations.prefix(limit))) {
            UserDefaults.appGroup?.set(data, forKey: key)
        }
    }
}

/// Adressvorschläge während der Eingabe, auf die Region Dresden ausgerichtet
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.050446, longitude: 13.737954),
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        )
    }

    func update(query: String) {
        if query.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(5))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    /// Wandelt einen Vorschlag in ein Ziel mit Koordinate um
    func resolve(_ completion: MKLocalSearchCompletion) async -> ConnectionStop? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let mapItem = try? await search.start().mapItems.first else { return nil }
        let coordinate = mapItem.location.coordinate
        return ConnectionStop(
            displayName: completion.title,
            location: StopCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }
}
