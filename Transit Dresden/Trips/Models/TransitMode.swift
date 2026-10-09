//
//  TransitMode.swift
//  Transit Dresden
//

import SwiftUI

/// Verkehrsmittel eines Abschnitts, abgeleitet aus dem Typ der VVO-Schnittstelle
enum TransitMode {
    case walk
    case bus
    case tram
    case suburbanRailway
    case train
    case ferry
    case cableway
    case other

    init(motType: String) {
        switch motType {
        case "Footpath": self = .walk
        case "CityBus", "IntercityBus", "PlusBus", "Bus": self = .bus
        case "Tram": self = .tram
        case "SuburbanRailway", "RapidTransit": self = .suburbanRailway
        case "Train": self = .train
        case "Ferry": self = .ferry
        case "Cableway": self = .cableway
        default: self = .other // Treppen, eingefügte Wartezeiten, Unbekanntes
        }
    }

    /// Abschnitt mit einem Fahrzeug (kein Fußweg, keine Treppe, keine Wartezeit)
    var isRide: Bool {
        self != .walk && self != .other
    }

    var systemImage: String {
        switch self {
        case .walk: "figure.walk"
        case .bus: "bus.fill"
        case .tram: "lightrail.fill"
        case .suburbanRailway, .train: "tram.fill"
        case .ferry: "ferry.fill"
        case .cableway: "cablecar.fill"
        case .other: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .bus: .blue
        case .tram: .orange
        case .suburbanRailway: .green
        case .train: .red
        case .ferry: .teal
        case .cableway: .brown
        case .walk, .other: .gray
        }
    }

    /// Bezeichnung einer Linie im Satz, z. B. "Die Buslinie 68".
    /// Zusammengeschrieben; nur "S-Bahn-Linie" wird durchgekoppelt, weil "S-Bahn" schon einen Bindestrich hat.
    var lineTitle: String {
        switch self {
        case .bus: "Buslinie"
        case .tram: "Straßenbahnlinie"
        case .suburbanRailway: "S-Bahn-Linie"
        case .train: "Zuglinie"
        case .ferry: "Fährlinie"
        case .cableway: "Seilbahnlinie"
        case .walk, .other: "Linie"
        }
    }

    var accessibilityName: String {
        switch self {
        case .walk: "Fußweg"
        case .bus: "Bus"
        case .tram: "Straßenbahn"
        case .suburbanRailway: "S-Bahn"
        case .train: "Zug"
        case .ferry: "Fähre"
        case .cableway: "Seilbahn"
        case .other: "Abschnitt"
        }
    }
}
