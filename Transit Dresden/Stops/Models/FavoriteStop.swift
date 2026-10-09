//
//  FavoriteStop.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 18.04.23.
//

import Foundation

@MainActor class FavoriteStop: ObservableObject {
    @Published var favorites: [Int]

    init() {
        if let data = UserDefaults.standard.data(forKey: "FavoriteStops") {
            if let decoded = try? JSONDecoder().decode([Int].self, from: data) {
                favorites = decoded
                return
            }
        }

        self.favorites = []
    }

    func isFavorite(stopID: Int) -> Bool {
        favorites.contains(stopID)
    }
}
