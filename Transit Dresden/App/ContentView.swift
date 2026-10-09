//
//  ContentView.swift
//  Transit Dresden
//
//  Created by Peter Lohse on 18.04.23.
//

import SwiftUI

struct ContentView: View {
    @StateObject var favoriteStops = FavoriteStop()

    var body: some View {
        GoView()
            .environmentObject(favoriteStops)
    }
}

#Preview {
    ContentView()
}
