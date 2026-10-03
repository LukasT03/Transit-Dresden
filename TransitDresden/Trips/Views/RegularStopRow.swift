//
//  RegularStopRow.swift
//  TransitDresden
//
//  Created by Peter Lohse on 21.04.23.
//

import SwiftUI

struct RegularStopRow: View {
    var regularStop: RegularStop
    var isFirst: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(regularStop.Name)
                    .accessibilityLabel("Haltestelle \(regularStop.Name)")
                Spacer()
                if regularStop.getPlatform() != nil {
                    Text(regularStop.getPlatform() ?? "")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .accessibilitySortPriority(-1)
                }
            }
            HStack {
                Text("\(isFirst ? regularStop.getDepartureTime() :  regularStop.getArrivalTime()) Uhr")
                    .accessibilityLabel("Geplante \(isFirst ? "Abfahrt " + regularStop.getDepartureTime() :  "Ankunft " + regularStop.getArrivalTime()) Uhr")
                if isFirst {
                    if regularStop.getTimeDifferenceDeparture() > 0 {
                        Text("+\(regularStop.getTimeDifferenceDeparture())")
                            .foregroundColor(Color.red)
                            .accessibilityLabel("\(regularStop.getTimeDifferenceDeparture()) \(regularStop.getTimeDifferenceDeparture() == 1 ? "Minute" : "Minuten") Verspätung")
                    } else if regularStop.getTimeDifferenceDeparture() < 0 {
                        Text("\(regularStop.getTimeDifferenceDeparture())")
                            .foregroundColor(Color.green)
                            .accessibilityLabel("\(abs(regularStop.getTimeDifferenceDeparture())) \(regularStop.getTimeDifferenceDeparture() == -1 ? "Minute" : "Minuten") früher")
                    }
                } else {
                    if regularStop.getTimeDifference() > 0 {
                        Text("+\(regularStop.getTimeDifference())")
                            .foregroundColor(Color.red)
                            .accessibilityLabel("\(regularStop.getTimeDifferenceDeparture()) \(regularStop.getTimeDifferenceDeparture() == 1 ? "Minute" : "Minuten") Verspätung")
                    } else if regularStop.getTimeDifference() < 0 {
                        Text("\(regularStop.getTimeDifference())")
                            .foregroundColor(Color.green)
                            .accessibilityLabel("\(abs(regularStop.getTimeDifferenceDeparture())) \(regularStop.getTimeDifferenceDeparture() == -1 ? "Minute" : "Minuten") früher")
                    }
                }
                Spacer()
                Text("\(isFirst ? regularStop.getRealDepartureTime() : regularStop.getRealArrivalTime()) Uhr")
                    .accessibilityLabel("Voraussichtliche \(isFirst ? "Abfahrt " + regularStop.getRealDepartureTime() :  "Ankunft " + regularStop.getRealArrivalTime()) Uhr")

            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
