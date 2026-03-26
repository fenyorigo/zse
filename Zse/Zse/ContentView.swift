//
//  ContentView.swift
//  Zse
//
//  Created by Bajan Peter on 2026-03-25.
//

import SwiftUI
import ZseCore

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZseRootView(appState: appState)
    }
}

#Preview {
    ContentView(appState: AppState())
}
