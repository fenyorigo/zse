//
//  ZseApp.swift
//  Zse
//
//  Created by Bajan Peter on 2026-03-25.
//

import AppKit
import SwiftUI
import ZseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@main
struct ZseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("zsé") {
            ContentView(appState: appState)
        }
        .commands {
            ZseCommands(appState: appState)
        }
    }
}
