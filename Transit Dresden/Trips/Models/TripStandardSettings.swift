//
//  TripStandardSettings.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 21.04.23.
//

import Foundation

struct TripStandardSettings: Hashable, Codable {
    var mot: [String]
    /// Gehgeschwindigkeit für alle Fußwege: "Slow", "Normal" oder "Fast". "Fast" plant etwa 80 % der normalen
    /// Gehzeit, "VeryFast" liefert dagegen unbrauchbare Wege.
    var walkingSpeed: String?
}
