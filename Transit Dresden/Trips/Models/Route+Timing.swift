//
//  Route+Timing.swift
//  Transit Dresden
//

import Foundation

/// Zeiten und Abschnitte einer Verbindung, wie die Los-Ansicht sie braucht
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

    var arrivalTime: Date? {
        PartialRoutes.reversed().lazy.compactMap { $0.getEndTime() }.first
    }

    /// Fußweg zum ersten Verkehrsmittel in Minuten, 0 wenn man schon an der Haltestelle steht
    var minutesToFirstStop: Int {
        guard !isWalkOnly, case .walk(let minutes) = legs.first else { return 0 }
        return minutes
    }

    /// Die geplante Losgehzeit ist vorbei, schaffen lässt sich die Verbindung nur noch im Laufschritt
    func needsRunning(at date: Date) -> Bool {
        guard !isWalkOnly, !startsAtStop, let leaveTime else { return false }
        return date > leaveTime
    }

    /// Erster Abschnitt mit einem Verkehrsmittel (kein Fußweg, keine Treppe, keine Wartezeit)
    var firstRide: PartialRoute? {
        firstRideIndex.map { PartialRoutes[$0] }
    }

    var firstRideIndex: Int? {
        PartialRoutes.firstIndex { TransitMode(motType: $0.Mot.type).isRide && $0.RegularStops != nil }
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

    /// Ein- und Ausstieg jeder Fahrt; nur dort zeigt der Ablauf den Steig
    var boardingAndAlightingStops: [RegularStop] {
        legs.flatMap { leg -> [RegularStop] in
            guard case .ride(let ride) = leg, let first = ride.RegularStops?.first, let last = ride.RegularStops?.last else {
                return []
            }
            return [first, last]
        }
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
