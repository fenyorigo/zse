import SwiftUI

public struct ZseRootView: View {
    @ObservedObject private var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ContentView()
            .environmentObject(appState)
    }
}
