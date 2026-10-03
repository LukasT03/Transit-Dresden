//
//  FavoriteStop.swift
//  TransitDresden
//
//  Created by Peter Lohse on 18.04.23.
//

import Foundation

extension UserDefaults {
    /// Gemeinsamer Speicher von App, Widget und Intents (App Group)
    static let appGroup = UserDefaults(suiteName: "group.com.lukastuchscherer.transit")
}

@MainActor class FavoriteStop: ObservableObject {
    @Published var favorites: [Int]

    init() {
        if let data = UserDefaults.appGroup?.data(forKey: "FavoriteStops") {
            if let decoded = try? JSONDecoder().decode([Int].self, from: data) {
                favorites = decoded
                return
            }
        }

        self.favorites = []
    }

    func add(stopID: Int) {
        if !isFavorite(stopID: stopID) {
            favorites.append(stopID)
            save()
        }
    }

    func remove(stopID: Int) {
        if let firstIndex = favorites.firstIndex(of: stopID) {
            favorites.remove(at: firstIndex)
            save()
        }
    }

    func isFavorite(stopID: Int) -> Bool {
        let cons = favorites.contains { element in
            if element == stopID {
                return true
            } else {
                return false
            }
        }
        return cons
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.appGroup?.set(encoded, forKey: "FavoriteStops")
        }
        // fürs Widget

        let sharedUserDefaults = UserDefaults.appGroup
        sharedUserDefaults?.set(favorites, forKey: "WidgetFavs")

    }
}
