//
//  TripService.swift
//  TransitDresden
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

    /// Verkehrsmittel für die Anfrage aus dem Verkehrsmittel-Filter
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
//        if (filter.taxi) {
//            mot.append("HailedSharedTaxi")
//        }

        return TripStandardSettings(mot: mot)
    }
}
