//
//  TripService.swift
//  Transit Dresden
//

import Foundation

/// Fragt Verbindungen bei der Routenplanung des VVO ab
enum TripService {
    private static let tripsURL = URL(string: "https://webapi.vvo-online.de/tr/trips")!
    private static let prevNextURL = URL(string: "https://webapi.vvo-online.de/tr/prevnext")!

    /// Lädt Verbindungen. Mit `isNext` werden über die SessionId der vorherigen Antwort spätere Verbindungen geladen.
    /// Die Schnittstelle antwortet gelegentlich fehlerhaft, deshalb wird mehrfach versucht.
    static func fetchTrips(_ tripRequest: TripRequest, isNext: Bool = false, attempts: Int = 3) async throws -> Trip {
        var request = URLRequest(url: isNext ? prevNextURL : tripsURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(tripRequest)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Transit Dresden", forHTTPHeaderField: "User-Agent")

        var lastError: Error?
        for attempt in 1...attempts {
            do {
                let (content, _) = try await URLSession.shared.data(for: request)
                return try JSONDecoder().decode(Trip.self, from: content)
            } catch {
                lastError = error
                print("TripService error (Versuch \(attempt) von \(attempts)): \(error)")
                if attempt < attempts {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // MARK: - Steige

    private static let departuresURL = URL(string: "https://webapi.vvo-online.de/dm")!

    /// Abfragen je Haltestelle, damit jede Haltestelle nur einmal abgefragt wird, auch wenn sie mehrfach im Ablauf steht
    @MainActor private static var platformLookups: [String: Task<Set<DeparturePlatform>?, Never>] = [:]

    /// Ob an einer Haltestelle mehrere Steige bedient werden. Grundlage sind die nächsten Abfahrten laut
    /// Abfahrtsmonitor, ergänzt um den Steig der Fahrt selbst (etwa ein reiner Ausstiegssteig an einer Endhaltestelle).
    /// Lässt es sich nicht ermitteln, gilt die Antwort "ja", damit der Steig im Zweifel sichtbar bleibt.
    @MainActor
    static func hasSeveralPlatforms(_ stop: RegularStop) async -> Bool {
        guard let platform = stop.Platform else { return false }
        let lookup = platformLookups[stop.DataId] ?? Task {
            try? await departurePlatforms(stopID: stop.DataId)
        }
        platformLookups[stop.DataId] = lookup
        guard let platforms = await lookup.value else {
            // beim nächsten Mal erneut versuchen
            platformLookups[stop.DataId] = nil
            return true
        }
        return platforms.union([platform]).count > 1
    }

    /// Steige der nächsten Abfahrten an einer Haltestelle. 50 Abfahrten reichen, um mehrere Steige zu erkennen:
    /// An großen Knoten tauchen ohnehin viele auf, an kleinen Haltestellen decken sie mehrere Stunden ab.
    private static func departurePlatforms(stopID: String) async throws -> Set<DeparturePlatform> {
        var request = URLRequest(url: departuresURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(DepartureMonitorRequest(stopid: stopID, limit: 50))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Transit Dresden", forHTTPHeaderField: "User-Agent")

        let (content, _) = try await URLSession.shared.data(for: request)
        let monitor = try JSONDecoder().decode(DepartureMonitor.self, from: content)
        guard let departures = monitor.Departures else {
            throw URLError(.badServerResponse)
        }
        return Set(departures.compactMap(\.Platform))
    }

    private struct DepartureMonitorRequest: Encodable {
        var stopid: String
        var limit: Int
        var format = "json"
    }

    private struct DepartureMonitor: Decodable {
        struct Departure: Decodable {
            var Platform: DeparturePlatform?
        }

        var Departures: [Departure]?
    }

    // MARK: - Verkehrsmittel

    /// Verkehrsmittel für die Anfrage aus dem Verkehrsmittel-Filter. Gegangen wird zügig:
    /// Mit normaler Gehgeschwindigkeit plant der VVO so vorsichtig, dass gut schaffbare Verbindungen fehlen.
    static func standardSettings(from filter: DepartureFilter) -> TripStandardSettings {
        var mot: [String] = []
        if filter.tram {
            mot.append("Tram")
        }
        if filter.bus {
            mot.append("CityBus")
            mot.append("IntercityBus")
            mot.append("PlusBus")
        }
        if filter.suburbanRailway {
            mot.append("SuburbanRailway")
        }
        if filter.train {
            mot.append("Train")
        }
        if filter.cableway {
            mot.append("Cableway")
        }
        if filter.ferry {
            mot.append("Ferry")
        }

        return TripStandardSettings(mot: mot, walkingSpeed: "Fast")
    }
}
