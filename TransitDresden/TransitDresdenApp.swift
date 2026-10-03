//
//  TransitDresdenApp.swift
//  TransitDresden
//
//  Created by Peter Lohse on 18.04.23.
//

import SwiftUI
import WidgetKit

@main
struct TransitDresdenApp: App {
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .dynamicTypeSize(.medium ... .large)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
