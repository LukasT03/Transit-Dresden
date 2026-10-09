//
//  PartialRoute.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 19.04.23.
//

import Foundation

struct PartialRoute: Hashable, Codable {
    var Mot: Mot
    var RegularStops: [RegularStop]?
    /// Dauer in Minuten laut Schnittstelle; wichtig für Fußwege beim Umsteigen, die ohne Haltestellen und Zeiten kommen
    var Duration: Int?

    func getStartTime() -> Date? {
        let regularStop = self.RegularStops?.first
        if regularStop == nil {
            return nil
        }

        var time = regularStop?.DepartureTime
        if regularStop?.DepartureRealTime != nil {
            time = regularStop?.DepartureRealTime
        }
        if time == nil {
            return nil
        }

        return DateParser.extractTimestamp(time: time!)
    }

    func getEndTime() -> Date? {
        let regularStop = self.RegularStops?.last
        if regularStop == nil {
            return nil
        }

        var time = regularStop?.ArrivalTime

        if regularStop?.ArrivalRealTime != nil {
            time = regularStop?.ArrivalRealTime
        }
        if time == nil {
            return nil
        }

        return DateParser.extractTimestamp(time: time!)
    }

    func getDuration() -> Int {
        let start: Double = getStartTime()?.timeIntervalSince1970 ?? 0
        let end: Double = getEndTime()?.timeIntervalSince1970 ?? 0
        return Int((end - start) / 60)
    }
}
