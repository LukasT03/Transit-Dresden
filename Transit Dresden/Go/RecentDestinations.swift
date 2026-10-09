//
//  RecentDestinations.swift
//  Transit Dresden
//

import Foundation

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
