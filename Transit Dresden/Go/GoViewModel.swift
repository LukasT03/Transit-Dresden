//
//  GoViewModel.swift
//  Transit Dresden
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
    /// Ein- und Ausstiege, an denen mehrere Steige bedient werden; nur dort zeigt der Ablauf den Steig.
    /// Steht schon fest, wenn die Verbindungen erscheinen, damit der Ablauf nicht nachträglich wächst.
    private(set) var platformStops: Set<RegularStop> = []
    /// IDs der Haltestellen, an denen man gerade steht. Steht man dort nur an einem anderen Steig als dem
    /// der ersten Fahrt, geht es im Ablauf "Zu Steig 3" statt "Zur Haltestelle".
    private(set) var nearbyStops: Set<String> = []

    @ObservationIgnored private var serviceSession: CLServiceSession?
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

        // Die Planung liefert nur Verbindungen, für die man noch rechtzeitig losgehen kann. Eine zweite, frühere
        // Abfrage bringt auch die, die man nur noch im Laufschritt schafft; das deckt Fußwege bis 10 Minuten ab.
        let now = Date.now
        let settings = TripService.standardSettings(from: DepartureFilter())
        let currentRequest = Self.tripRequest(from: from, to: to, at: now, settings: settings)
        let earlierRequest = Self.tripRequest(from: from, to: to, at: now.addingTimeInterval(-5 * 60), settings: settings)
        async let current = TripService.fetchTrips(currentRequest)
        // ohne die frühere Abfrage fehlen nur die knappen Verbindungen, ihr Fehlschlagen ist also kein Fehler
        async let earlier = try? TripService.fetchTrips(earlierRequest)
        do {
            let trip = try await current
            let earlierRoutes = Self.startingAtStop((await earlier)?.Routes ?? [], from: location)
            var routes = Self.merged(Self.startingAtStop(trip.Routes, from: location), earlierRoutes)
            let nearbyStops = Self.stopsNear(location)
            // Beim ersten Laden gleich zeigen und erst danach nachladen, damit die Ansicht nicht darauf wartet.
            // Beim Aktualisieren erst alles zusammen, sonst schrumpfte die Auswahl jedes Mal kurz.
            var shownAt: ContinuousClock.Instant?
            if !silent, !Self.displayed(routes, at: .now).isEmpty {
                guard await show(routes, nearbyStops: nearbyStops, for: destination, keepSelection: false) else { return }
                shownAt = .now
            }

            // Der VVO liefert je Abfrage nur etwa 4 Verbindungen über rund 10 Minuten. Spätere nachladen, bis nach
            // dem Aussortieren genug zur Wahl stehen; jedes Nachladen braucht die Antwort des vorigen.
            var nextRequest = currentRequest
            nextRequest.sessionId = trip.SessionId
            nextRequest.previous = false
            for _ in 0..<2 {
                guard Self.displayed(routes, at: .now).count < 5,
                      let next = try? await TripService.fetchTrips(nextRequest, isNext: true) else {
                    break
                }
                // die Antwort enthält auch alle bisherigen Verbindungen
                routes = Self.merged(Self.startingAtStop(next.Routes, from: location), earlierRoutes)
            }
            // Nachgeladene erst, wenn die Ansicht steht: Kämen sie mit der unteren Leiste, wirkte es zufällig.
            // Gezählt ab dem Einblenden, ein langsames Nachladen wartet also nicht noch zusätzlich.
            if let shownAt {
                try? await Task.sleep(until: shownAt + .seconds(1))
            }
            // die neuen gehen später los und kommen hinten dazu, die gewählte bleibt
            await show(routes, nearbyStops: nearbyStops, for: destination, keepSelection: true)
        } catch {
            if !Task.isCancelled {
                fail("Die Verbindungen konnten nicht geladen werden.", silent: silent)
            }
        }
    }

    private static func tripRequest(from origin: String, to destination: String, at time: Date, settings: TripStandardSettings) -> TripRequest {
        TripRequest(
            time: time.ISO8601Format(),
            isarrivaltime: false,
            origin: origin,
            destination: destination,
            standardSettings: settings
        )
    }

    /// Verbindungen beider Abfragen, ohne doppelte. Reine Fußwege nur aus der aktuellen,
    /// die frühere liefert sie mit veralteter Losgehzeit.
    private static func merged(_ current: [Route], _ earlier: [Route]) -> [Route] {
        var seen = Set(current.map(identity))
        var routes = current
        for route in earlier where !route.isWalkOnly && seen.insert(identity(route)).inserted {
            routes.append(route)
        }
        return routes
    }

    /// Kennung über alle Fahrten einer Verbindung; die erste allein reicht nicht,
    /// weil eine Antwort nach derselben ersten Fahrt verschieden weiterfahren kann
    private static func identity(_ route: Route) -> String {
        route.legs.compactMap { leg -> String? in
            guard case .ride(let ride) = leg else { return nil }
            return "\(ride.Mot.Name ?? "")|\(ride.RegularStops?.first?.DepartureTime ?? "")"
        }
        .joined(separator: ",")
    }

    /// Zeigt die Verbindungen, sobald die Steige ihrer Haltestellen geklärt sind.
    /// false, wenn inzwischen ein anderes Ziel gewählt wurde.
    @discardableResult
    private func show(_ routes: [Route], nearbyStops: Set<String>, for destination: ConnectionStop, keepSelection: Bool) async -> Bool {
        // alle Haltestellen gleichzeitig; schon bekannte kosten dank Zwischenspeicher nichts
        let platformStops = await Self.stopsWithSeveralPlatforms(on: routes)
        guard self.destination == destination else { return false }
        self.platformStops = platformStops
        self.nearbyStops = nearbyStops
        apply(routes, keepSelection: keepSelection)
        return true
    }

    // MARK: - An der Haltestelle

    /// Steht man schon am Steig der ersten Fahrt (höchstens 50 m), entfällt der Fußweg dorthin. Der VVO plant ab
    /// der nächsten Adresse und setzt deshalb selbst dann ein, zwei Minuten an, wenn man direkt daneben steht.
    private static func startingAtStop(_ routes: [Route], from location: CLLocation) -> [Route] {
        let coordinate = StopCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard let position = wgs2gk(wgs: coordinate) else { return routes }
        return routes.map { route in
            // Der VVO liefert Steige in Gauß-Krüger-Metern: Longitude ist der Rechts-, Latitude der Hochwert
            guard let rideIndex = route.firstRideIndex, rideIndex > 0,
                  let platform = route.PartialRoutes[rideIndex].RegularStops?.first,
                  hypot(Double(platform.Longitude) - position.x, Double(platform.Latitude) - position.y) <= 50 else {
                return route
            }
            var route = route
            route.PartialRoutes.removeFirst(rideIndex)
            return route
        }
    }

    /// Haltestellen, deren Mittelpunkt höchstens 100 m entfernt ist; so weit liegen auch die Steige großer
    /// Haltestellen meist auseinander
    private static func stopsNear(_ location: CLLocation) -> Set<String> {
        Set(stops.lazy
            .filter { location.distance(from: CLLocation(latitude: $0.coordinates.latitude, longitude: $0.coordinates.longitude)) <= 100 }
            .map { String($0.stopID) })
    }

    // MARK: - Auswahl der Verbindung

    private func apply(_ newRoutes: [Route], keepSelection: Bool) {
        let previousKey = keepSelection ? selectedRoute.map(Self.key) : nil
        routes = Self.displayed(newRoutes, at: .now)

        if let previousKey, let index = routes.firstIndex(where: { Self.key($0) == previousKey }) {
            selectedIndex = index
        } else {
            selectedIndex = Self.bestIndex(in: routes) ?? 0
        }
        phase = routes.isEmpty ? .failed("Keine erreichbare Verbindung gefunden.") : .loaded
    }

    /// Ein- und Ausstiege aller Verbindungen, an denen mehrere Steige bedient werden. Die Abfragen laufen
    /// gleichzeitig und bleiben im TripService zwischengespeichert, beim Aktualisieren kosten sie also nichts.
    private static func stopsWithSeveralPlatforms(on routes: [Route]) async -> Set<RegularStop> {
        await withTaskGroup(of: RegularStop?.self) { group in
            for stop in Set(routes.flatMap(\.boardingAndAlightingStops)) {
                group.addTask {
                    await TripService.hasSeveralPlatforms(stop) ? stop : nil
                }
            }
            var stops: Set<RegularStop> = []
            for await stop in group {
                if let stop {
                    stops.insert(stop)
                }
            }
            return stops
        }
    }

    private func fail(_ message: String, silent: Bool) {
        if !silent || routes.isEmpty {
            routes = []
            phase = .failed(message)
        }
    }

    /// Die Verbindungen, die zur Wahl stehen, chronologisch
    private static func displayed(_ routes: [Route], at date: Date) -> [Route] {
        // Überholte zuletzt: Eine verpasste oder zu weit entfernte soll keine verdrängen, die bleibt
        let candidates = withoutLongWalks(catchable(routes, at: date))
        return chronological(withoutOutdated(candidates))
    }

    /// Nur Verbindungen, die man noch schafft, notfalls im Laufschritt
    private static func catchable(_ routes: [Route], at date: Date) -> [Route] {
        routes.filter { route in
            route.isWalkOnly || (route.lastChance.map { $0 >= date } ?? false)
        }
    }

    /// Ohne Verbindungen mit mehr als 8 Minuten Fußweg zur ersten Haltestelle, solange es eine mit kürzerem gibt;
    /// weit weg von jeder Haltestelle bliebe sonst nichts übrig. Reine Fußwege bleiben.
    private static func withoutLongWalks(_ routes: [Route]) -> [Route] {
        let limit = 8
        guard routes.contains(where: { !$0.isWalkOnly && $0.minutesToFirstStop <= limit }) else {
            return routes
        }
        return routes.filter { $0.minutesToFirstStop <= limit }
    }

    /// Ohne überholte Verbindungen. Reine Fußwege bleiben außen vor, weil man sie jederzeit beginnen kann.
    private static func withoutOutdated(_ routes: [Route]) -> [Route] {
        routes.filter { route in
            !routes.contains { other in isOutdated(route, by: other) }
        }
    }

    /// Bei `other` muss man nicht früher losgehen und kommt trotzdem nicht später an;
    /// ist beides gleich, hat `other` weniger Umstiege
    private static func isOutdated(_ route: Route, by other: Route) -> Bool {
        guard !route.isWalkOnly, !other.isWalkOnly,
              let leave = route.leaveTime, let arrival = route.arrivalTime,
              let otherLeave = other.leaveTime, let otherArrival = other.arrivalTime,
              otherLeave >= leave, otherArrival <= arrival else {
            return false
        }
        if otherLeave > leave || otherArrival < arrival {
            return true
        }
        return other.Interchanges < route.Interchanges
    }

    private static func chronological(_ routes: [Route]) -> [Route] {
        routes.sorted { ($0.leaveTime ?? .distantFuture) < ($1.leaveTime ?? .distantFuture) }
    }

    /// Früheste Ankunft, danach weniger Umstiege, danach späteres Losgehen (weniger Wartezeit).
    /// Verbindungen, für die man rennen müsste, nur wenn keine andere bleibt.
    static func bestIndex(in routes: [Route], at date: Date = .now) -> Int? {
        let walkable = routes.indices.filter { !routes[$0].needsRunning(at: date) }
        let candidates = walkable.isEmpty ? Array(routes.indices) : walkable
        return candidates.min { a, b in
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
        model.routes = chronological(routes.map { shifted($0, by: offset) })
        model.selectedIndex = bestIndex(in: model.routes) ?? 0
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

extension Route {
    /// Zeitpunkt, zu dem man losgehen muss: Abfahrt des ersten Verkehrsmittels (mit Echtzeit) minus Fußweg dorthin.
    /// Selbst gerechnet, weil der VVO die Zeiten des Fußwegs bei Verspätungen nur manchmal mitverschiebt.
    /// Bei reinem Fußweg der Beginn laut Planung.
    var leaveTime: Date? {
        guard let departure = firstRide?.getStartTime() else {
            return PartialRoutes.lazy.compactMap { $0.getStartTime() }.first
        }
        return departure.addingTimeInterval(-Double(minutesToFirstStop * 60))
    }

    /// Fußweg zum ersten Verkehrsmittel in Minuten, 0 wenn man schon an der Haltestelle steht
    var minutesToFirstStop: Int {
        guard !isWalkOnly, case .walk(let minutes) = legs.first else { return 0 }
        return minutes
    }

    var arrivalTime: Date? {
        PartialRoutes.reversed().lazy.compactMap { $0.getEndTime() }.first
    }

    /// Erster Abschnitt mit einem Verkehrsmittel (kein Fußweg, keine Treppe, keine Wartezeit)
    var firstRide: PartialRoute? {
        firstRideIndex.map { PartialRoutes[$0] }
    }

    var firstRideIndex: Int? {
        PartialRoutes.firstIndex { TransitMode(motType: $0.Mot.type).isRide && $0.RegularStops != nil }
    }

    /// Bis dahin ist die Verbindung noch zu schaffen: Für den Fußweg zur Haltestelle bleibt mindestens
    /// die Hälfte der geplanten Gehzeit. Steht man schon an der Haltestelle, bis zur Abfahrt.
    var lastChance: Date? {
        guard let departure = firstRide?.getStartTime() else { return nil }
        return departure.addingTimeInterval(-Double(minutesToFirstStop * 60) / 2)
    }

    /// Die geplante Losgehzeit ist vorbei, schaffen lässt sich die Verbindung nur noch im Laufschritt
    func needsRunning(at date: Date) -> Bool {
        guard !isWalkOnly, !startsAtStop, let leaveTime else { return false }
        return date > leaveTime
    }

    /// Ein- und Ausstieg jeder Fahrt; nur dort zeigt der Ablauf den Steig
    var boardingAndAlightingStops: [RegularStop] {
        legs.flatMap { leg -> [RegularStop] in
            guard case .ride(let ride) = leg, let first = ride.RegularStops?.first, let last = ride.RegularStops?.last else {
                return []
            }
            return [first, last]
        }
    }

    /// Ohne Verkehrsmittel, nur zu Fuß: Losgehen ist jederzeit möglich, die geplanten Zeiten sind nur ein Beispiel
    var isWalkOnly: Bool {
        firstRide == nil
    }

    /// Beginnt direkt mit einer Fahrt, ohne Fußweg davor: Man steht schon an der Haltestelle
    var startsAtStop: Bool {
        if case .ride = legs.first {
            return true
        }
        return false
    }

    /// Fußwege (aufeinanderfolgende zusammengefasst) und Fahrten; Treppen und Wartezeiten entfallen
    var legs: [RouteLeg] {
        var legs: [RouteLeg] = []
        for partialRoute in PartialRoutes {
            let mode = TransitMode(motType: partialRoute.Mot.type)
            if mode == .walk {
                // Die Dauer laut Schnittstelle: Fußwege beim Umsteigen haben keine Zeiten, und die des ersten
                // Fußwegs verschiebt der VVO bei Verspätungen nicht verlässlich mit
                let minutes = partialRoute.Duration ?? partialRoute.getDuration()
                guard minutes > 0 else { continue }
                if case .walk(let previous) = legs.last {
                    legs[legs.count - 1] = .walk(minutes: previous + minutes)
                } else {
                    legs.append(.walk(minutes: minutes))
                }
            } else if mode.isRide, partialRoute.RegularStops != nil {
                legs.append(.ride(partialRoute))
            }
        }
        return legs
    }
}

/// Abschnitt einer Verbindung, wie ihn Übersicht und Ablauf zeigen
enum RouteLeg {
    case walk(minutes: Int)
    case ride(PartialRoute)
}

/// Zuletzt gewählte Ziele der Los-Ansicht
enum RecentDestinations {
    private static let key = "RecentDestinations"
    private static let limit = 5

    static func load() -> [ConnectionStop] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let destinations = try? JSONDecoder().decode([ConnectionStop].self, from: data) else {
            return []
        }
        // ältere Einträge hatten den Ort im Namen ("Klosterteichplatz Dresden"); bei Haltestellen gilt der reine Name
        return destinations.map { destination in
            guard let stop = destination.stop else { return destination }
            var destination = destination
            destination.displayName = stop.name
            return destination
        }
    }

    static func add(_ destination: ConnectionStop) {
        var destinations = load().filter { identity(of: $0) != identity(of: destination) }
        destinations.insert(destination, at: 0)
        if let data = try? JSONEncoder().encode(Array(destinations.prefix(limit))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Haltestellen über ihre ID, weil Namen ohne Ort nicht eindeutig sind ("Bahnhof"); Adressen über den Namen
    private static func identity(of destination: ConnectionStop) -> String {
        destination.stop.map { "stop:\($0.stopID)" } ?? "place:\(destination.displayName)"
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
