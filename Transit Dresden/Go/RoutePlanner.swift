//
//  RoutePlanner.swift
//  Transit Dresden
//

import Foundation
import CoreLocation

/// Entscheidet, welche Verbindungen die Los-Ansicht anbietet: holt sie beim VVO, erkennt, ob man schon an der
/// Haltestelle steht, sortiert unbrauchbare aus und schlägt die beste vor. Alle Stellschrauben stehen hier oben.
struct RoutePlanner {
    // MARK: - Stellschrauben

    /// Alle Verkehrsmittel. Gegangen wird zügig ("Fast", etwa 80 % der normalen Gehzeit, gilt für alle Fußwege):
    /// Mit normaler Gehgeschwindigkeit plant der VVO so vorsichtig, dass gut schaffbare Verbindungen fehlen.
    /// "VeryFast" liefert dagegen unbrauchbare Wege.
    static let settings = TripStandardSettings(
        mot: ["Tram", "CityBus", "IntercityBus", "PlusBus", "SuburbanRailway", "Train", "Cableway", "Ferry"],
        walkingSpeed: "Fast"
    )

    /// Der VVO liefert nur Verbindungen, für die man noch rechtzeitig losgehen kann. Eine zweite, um so viel
    /// frühere Abfrage bringt auch die, die man nur noch im Laufschritt schafft. Mit `minimumWalkShare` deckt das
    /// Fußwege bis 10 Minuten ab, also alle bis `maximumWalkMinutes`.
    static let lookBack: TimeInterval = 5 * 60

    /// Anteil der geplanten Gehzeit zur ersten Haltestelle, der bis zur Abfahrt mindestens bleiben muss.
    /// Rennen ist etwa doppelt so schnell wie Gehen, mit weniger Zeit ist die Verbindung nicht mehr zu schaffen.
    static let minimumWalkShare = 0.5

    /// Längster Fußweg zur ersten Haltestelle in Minuten, solange es Verbindungen mit kürzerem gibt
    static let maximumWalkMinutes = 8

    /// So viele Verbindungen sollen nach dem Aussortieren zur Wahl stehen; der VVO liefert je Abfrage nur etwa 4
    /// über rund 10 Minuten
    static let preferredCount = 5

    /// Höchstens so oft spätere Verbindungen nachladen; jedes Mal dauert etwa 0,7 s
    static let maximumLoadMore = 2

    /// Bis zu dieser Entfernung vom Steig der ersten Fahrt steht man schon dort, in Metern. Ein Tram-Steig ist
    /// 45–60 m lang, GPS liegt zwischen Häusern oft 10–30 m daneben.
    static let platformRadius = 50.0

    /// Bis zu dieser Entfernung vom Mittelpunkt einer Haltestelle steht man an ihr, in Metern. Die Steige
    /// kleiner Haltestellen liegen 40–60 m vom Mittelpunkt, die großer bis etwa 130 m.
    static let stopRadius = 100.0

    // MARK: - Planung

    /// IDs der Haltestellen, an denen man gerade steht (wie `RegularStop.DataId`)
    let nearbyStops: Set<String>
    private let location: CLLocation
    /// Alle bisher geladenen Verbindungen, noch nicht aussortiert
    private var routes: [Route]
    /// Verbindungen der früheren Abfrage; das Nachladen baut nur auf der aktuellen auf
    private let earlierRoutes: [Route]
    /// Abfrage für spätere Verbindungen in der Sitzung der aktuellen
    private let nextRequest: TripRequest

    /// Fragt die ersten Verbindungen ab, ab jetzt und zurückdatiert gleichzeitig
    init(from origin: String, to destination: String, location: CLLocation) async throws {
        let now = Date.now
        let currentRequest = Self.request(from: origin, to: destination, at: now)
        let earlierRequest = Self.request(from: origin, to: destination, at: now.addingTimeInterval(-Self.lookBack))
        async let current = TripService.fetchTrips(currentRequest)
        // ohne die frühere Abfrage fehlen nur die knappen Verbindungen, ihr Fehlschlagen ist also kein Fehler
        async let earlier = try? TripService.fetchTrips(earlierRequest)
        let trip = try await current

        self.location = location
        nearbyStops = Self.stopIDs(near: location)
        earlierRoutes = Self.startingAtStop((await earlier)?.Routes ?? [], from: location)
        routes = Self.merged(Self.startingAtStop(trip.Routes, from: location), earlierRoutes)
        var nextRequest = currentRequest
        nextRequest.sessionId = trip.SessionId
        nextRequest.previous = false
        self.nextRequest = nextRequest
    }

    /// Die Verbindungen, die zur Wahl stehen, chronologisch nach Losgehzeit
    func options(at date: Date = .now) -> [Route] {
        // Überholte zuletzt: Eine verpasste oder zu weit entfernte soll keine verdrängen, die bleibt
        let candidates = Self.withoutLongWalks(Self.catchable(routes, at: date))
        return Self.chronological(Self.withoutOutdated(candidates))
    }

    /// Lädt spätere Verbindungen nach, bis genug zur Wahl stehen. Jedes Nachladen braucht die Antwort des vorigen;
    /// schlägt eines fehl, bleibt es bei den bisherigen.
    mutating func loadMore() async {
        for _ in 0..<Self.maximumLoadMore {
            guard options().count < Self.preferredCount,
                  let next = try? await TripService.fetchTrips(nextRequest, isNext: true) else {
                return
            }
            // die Antwort enthält auch alle bisherigen Verbindungen
            routes = Self.merged(Self.startingAtStop(next.Routes, from: location), earlierRoutes)
        }
    }

    /// Vorschlag: früheste Ankunft, danach weniger Umstiege, danach späteres Losgehen (weniger Wartezeit).
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

    static func chronological(_ routes: [Route]) -> [Route] {
        routes.sorted { ($0.leaveTime ?? .distantFuture) < ($1.leaveTime ?? .distantFuture) }
    }

    // MARK: - Abfragen

    private static func request(from origin: String, to destination: String, at time: Date) -> TripRequest {
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

    // MARK: - An der Haltestelle

    /// Steht man schon am Steig der ersten Fahrt, entfällt der Fußweg dorthin. Der VVO plant ab der nächsten
    /// Adresse und setzt deshalb selbst dann ein, zwei Minuten an, wenn man direkt daneben steht.
    private static func startingAtStop(_ routes: [Route], from location: CLLocation) -> [Route] {
        let coordinate = StopCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard let position = wgs2gk(wgs: coordinate) else { return routes }
        return routes.map { route in
            // Der VVO liefert Steige in Gauß-Krüger-Metern: Longitude ist der Rechts-, Latitude der Hochwert
            guard let rideIndex = route.firstRideIndex, rideIndex > 0,
                  let platform = route.PartialRoutes[rideIndex].RegularStops?.first,
                  hypot(Double(platform.Longitude) - position.x, Double(platform.Latitude) - position.y) <= platformRadius else {
                return route
            }
            var route = route
            route.PartialRoutes.removeFirst(rideIndex)
            return route
        }
    }

    private static func stopIDs(near location: CLLocation) -> Set<String> {
        Set(stops.lazy
            .filter { location.distance(from: CLLocation(latitude: $0.coordinates.latitude, longitude: $0.coordinates.longitude)) <= stopRadius }
            .map { String($0.stopID) })
    }

    // MARK: - Aussortieren

    /// Nur Verbindungen, die man noch schafft, notfalls im Laufschritt
    private static func catchable(_ routes: [Route], at date: Date) -> [Route] {
        routes.filter { route in
            route.isWalkOnly || (lastChance(for: route).map { $0 >= date } ?? false)
        }
    }

    /// Bis dahin ist die Verbindung noch zu schaffen: Für den Fußweg zur ersten Haltestelle bleibt mindestens
    /// `minimumWalkShare` der geplanten Gehzeit. Steht man schon an der Haltestelle, bis zur Abfahrt.
    private static func lastChance(for route: Route) -> Date? {
        guard let departure = route.firstRide?.getStartTime() else { return nil }
        return departure.addingTimeInterval(-Double(route.minutesToFirstStop * 60) * minimumWalkShare)
    }

    /// Ohne zu lange Fußwege zur ersten Haltestelle, solange es Verbindungen mit kürzerem gibt;
    /// weit weg von jeder Haltestelle bliebe sonst nichts übrig. Reine Fußwege bleiben.
    private static func withoutLongWalks(_ routes: [Route]) -> [Route] {
        guard routes.contains(where: { !$0.isWalkOnly && $0.minutesToFirstStop <= maximumWalkMinutes }) else {
            return routes
        }
        return routes.filter { $0.minutesToFirstStop <= maximumWalkMinutes }
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
}
