//
//  TripSectionViewModel.swift
//  Transit Dresden
//
//  Created by Kiara on 26.10.23.
//

import Foundation
import SwiftUI

class TripSectionViewModel: ObservableObject {
    @Published var route: Route
    @Published var routesWithWaitingTimeUnder2Min: [PartialRoute] = []

    init(route: Route) {
        self.route = route
        insertWaitingTimePartialRoute()
    }

    func getDuration(_ partialRoute: PartialRoute) -> (Int, String) {
        if partialRoute.Mot.type == "Footpath" && partialRoute.hasNoTime() {
            return  getWaitingTime(partialRoute, routes: route.PartialRoutes)
        }
        return (partialRoute.getDuration(), "")
    }

    func getWaitingTime(_ e: PartialRoute, routes: [PartialRoute]) -> (Int, String) {
        var value = 0
        var str = "Wartezeit"

        routes.forEach { f in
            if e == f {
                guard let index = routes.firstIndex(of: e) else { return }
                if index - 1 < 0 || index + 1 >= routes.count {
                    return
                }

                let defaultDate = Date()
                var date1 = defaultDate
                var date2  = defaultDate
                var beforeIndex = index - 1
                var afterIndex = index + 1

                while routes[beforeIndex].getDuration() == 0 && beforeIndex > 0 {
                    let item =  routes[beforeIndex]
                    if item.Mot.type == "MobilityStairsUp" {
                        str += " | Treppe ↑"
                    } else if item.Mot.type == "MobilityStairsDown" {
                        str += " | Treppe ↓"
                    }
                    beforeIndex -= 1
                }

                while routes[afterIndex].getDuration() == 0 && afterIndex <=  routes.count {
                    let item =  routes[afterIndex]
                    if item.Mot.type == "MobilityStairsUp" {
                        str += " | Treppe ↑"
                    } else if item.Mot.type == "MobilityStairsDown" {
                        str += " | Treppe ↓"
                    }
                    afterIndex += 1
                }

                date1 = routes[beforeIndex].getEndTime() ?? defaultDate
                date2 = routes[afterIndex].getStartTime() ?? defaultDate

                let difference = Calendar.current.dateComponents([.minute], from: date1, to: date2).minute

                value = difference ?? 0
            }
        }

        if value < 0 {
            return (0, str)
        }
        return (value, str)
    }

    /// Insert waiting time as partial routes into the route
    func insertWaitingTimePartialRoute() {
        routesWithWaitingTimeUnder2Min = []

        var arr: [PartialRoute] = []

        for i in 0..<route.PartialRoutes.count {
            let partialRoute = route.PartialRoutes[i]
            let before: PartialRoute? = arr.count >= 1 ? arr.last : nil

            // Wartezeit 1
            if partialRoute.getStartTime() == nil || partialRoute.getEndTime() == nil {
                continue
            }

            let start = partialRoute.getStartTime() ?? Date()
            let end = partialRoute.getEndTime() ?? Date()

            // Insert Wartezeit
            if before != nil {
                if before!.getEndTime() != start {
                    guard let insertedStart = before?.getEndTime() else {
                        continue
                    }
                    guard let  insertedEnd = partialRoute.getStartTime() else {
                        continue
                    }
                    let startTime = "/Date(\(Int(insertedStart.timeIntervalSince1970)*1000)-0000)/"
                    let endime = "/Date(\(Int(insertedEnd.timeIntervalSince1970)*1000)-0000)/"

                    let x =  PartialRoute(Mot: Mot(type: "InsertedWaiting"), RegularStops: [
                        RegularStop(ArrivalTime: startTime, DepartureTime: startTime, Place: "", Name: "x", type: "", Latitude: -1, Longitude: -1, DataId: "-1"),
                        RegularStop(ArrivalTime: endime, DepartureTime: endime, Place: "", Name: "x", type: "", Latitude: -1, Longitude: -1, DataId: "-1")
                    ])
                    arr.append(x)
                }
            }
            // Add current element
            if start != end {
                arr.append(partialRoute)
            }
        }
        routesWithWaitingTimeUnder2Min =  arr
    }

}
