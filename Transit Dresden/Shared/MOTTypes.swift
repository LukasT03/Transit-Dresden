//
//  MOTTypes.swift
//  Transit Dresden
//
//  Created by Tom Braune on 20.04.25.
//

import SwiftUI

enum MOTType {
    case Tram, Bus, Train, CableCar, Boat, Default, Walking, Up, Down
}

// accessabiity Lables

func getAccessibilityLabelStandard(motType: MOTType) -> String {
    switch motType {
    case .Tram:
        return "Straßenbahn"
    case .Bus:
        return "Bus"
    case .Train:
        return "Zug"
    case .CableCar:
        return "Standseilbahn/Schwebebahn"
    case .Boat:
        return "Fähre"
    case .Default:
        return ""
    case .Up:
        return "Treppe aufwärts"
    case .Down:
        return "Treppe abwärts"
    case .Walking:
        return "Zu Fuß"
    }
}

func getAccessibilityLabelEFA(iconId: Int) -> String {
    switch iconId {
    case 4:
        return getAccessibilityLabelStandard(motType: .Tram)
    case 3:
        return getAccessibilityLabelStandard(motType: .Bus)
    case 2, 6:
        return getAccessibilityLabelStandard(motType: .Train)
    case 9:
        return getAccessibilityLabelStandard(motType: .CableCar)
    case 10:
        return getAccessibilityLabelStandard(motType: .Boat)
    default:
        return getAccessibilityLabelStandard(motType: .Default)
    }
}

func getAccessibilityLabelVVO(motType: String) -> String {
    switch motType {
    case "Tram":
        return getAccessibilityLabelStandard(motType: .Tram)
    case "CityBus", "PlusBus", "Bus", "IntercityBus":
        return getAccessibilityLabelStandard(motType: .Bus)
    case "Train", "RapidTransit", "SuburbanRailway":
        return getAccessibilityLabelStandard(motType: .Train)
    case "Cableway":
        return getAccessibilityLabelStandard(motType: .CableCar)
    case "Ferry":
        return getAccessibilityLabelStandard(motType: .Boat)
    case "Footpath":
        return getAccessibilityLabelStandard(motType: .Walking)
    case "MobilityStairsUp":
        return getAccessibilityLabelStandard(motType: .Up)
    case "MobilityStairsDown":
        return getAccessibilityLabelStandard(motType: .Down)
    default:
        return getAccessibilityLabelStandard(motType: .Default)
    }
}

// icons

func getIconStandard(motType: MOTType) -> String {
    switch motType {
    case .Tram:
        return "🚊"
    case .Bus:
        return "🚍"
    case .Train:
        return "🚆"
    case .CableCar:
        return "🚞"
    case .Boat:
        return "⛴️"
    case .Default:
        return "🚊"
    case .Up:
        return "📈"
    case .Down:
        return "📉"
    case .Walking:
        return "🚶"
    }
}

func getIconEFA(iconId: Int) -> String {
    switch iconId {
    case 4:
        return getIconStandard(motType: .Tram)
    case 3:
        return getIconStandard(motType: .Bus)
    case 2, 6:
        return getIconStandard(motType: .Train)
    case 9:
        return getIconStandard(motType: .CableCar)
    case 10:
        return getIconStandard(motType: .Boat)
    default:
        return getIconStandard(motType: .Default)
    }
}

func getIconVVO(motType: String) -> String {
    switch motType {
    case "Tram":
        return  getIconStandard(motType: .Tram)
    case "CityBus", "PlusBus", "Bus", "IntercityBus":
        return getIconStandard(motType: .Bus)
    case "Train", "RapidTransit", "SuburbanRailway":
        return getIconStandard(motType: .Train)
    case "Cableway":
        return getIconStandard(motType: .CableCar)
    case "Ferry":
        return getIconStandard(motType: .Boat)
    case "Footpath":
        return getIconStandard(motType: .Walking)
    case "MobilityStairsUp":
        return getIconStandard(motType: .Up)
    case "MobilityStairsDown":
        return getIconStandard(motType: .Down)
    default:
        return getIconStandard(motType: .Default)
    }
}

// Colors
