//
//  DepartureInfoView.swift
//  TransitDresden
//
//  Created by Tom Braune on 23.03.25.
//

import Foundation
import SwiftUI

struct DepartureInfoView: View {
    let stopEvent: StopEvent

    var body: some View {
        // only use after check for stopEvent.infos exists
        Group {
            VStack {
                List(stopEvent.infos!, id: \.self) { info in
                    ForEach(info.infoLinks, id: \.self) { link in
                        DepartureInfoViewRow(infoLink: link)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Meldungen für \(stopEvent.getName())")
    }
}
