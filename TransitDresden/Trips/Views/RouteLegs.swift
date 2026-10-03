//
//  RouteLegs.swift
//  TransitDresden
//
//  Created by Peter Lohse on 19.04.23.
//

import SwiftUI

/// Abschnitte einer Route (Fußwege, Wartezeiten, Fahrten mit ihren Haltestellen)
struct RouteLegs: View {
    var vm: TripSectionViewModel

    var body: some View {
        ForEach(vm.routesWithWaitingTimeUnder2Min, id: \.self) { partialRoute in
            if partialRoute.Mot.type == "InsertedWaiting" && partialRoute.getDuration() > 0 {
                PartialRouteRowWaitingTime(time: partialRoute.getDuration(), text: partialRoute.getName())
            }
            if partialRoute.RegularStops == nil {
                if partialRoute.getDuration() == 0 {
                    let tup = vm.getDuration(partialRoute)
                    if tup.0 > 0 {
                        PartialRouteRowWaitingTime(time: tup.0, text: tup.1)
                    }
                } else {
                    PartialRouteRow(partialRoute: partialRoute)
                }
            } else {
                if partialRoute.Mot.type != "InsertedWaiting" {
                    // actual tram/bus etc parts
                    DisclosureGroup {
                        ForEach(partialRoute.RegularStops ?? [], id: \.self) { regularStop in
                            ZStack {
                                NavigationLink(value: regularStop.getStop() ?? stops[0]) {
                                    EmptyView()
                                }
                                .opacity(0.0)
                                .buttonStyle(.plain)

                                RegularStopRow(regularStop: regularStop, isFirst: partialRoute.RegularStops?.first?.DataId == regularStop.DataId)
                            }
                        }
                    } label: {
                        PartialRouteRow(partialRoute: partialRoute)
                    }}
            }
        }
    }
}

#Preview {
    NavigationStack {
        List {
            RouteLegs(vm: TripSectionViewModel(route: tripTmp.Routes[0]))
        }
    }
}
