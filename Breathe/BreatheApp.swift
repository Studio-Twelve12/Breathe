//
//  BreatheApp.swift
//  Breathe
//
//  Originally developed by Lucid. Acquired by and maintained by Studio 12.
//  Copyright © 2026 Studio 12. All rights reserved.
//

import SwiftUI

@main
struct BreatheApp: App {
    @StateObject private var monitor = SystemMonitor()

    var body: some Scene {
        // An explicit title string alongside the icon forces macOS to
        // allocate proper tracking width in the system menu bar.
        MenuBarExtra("Breathe", systemImage: "wind") {
            MenuBarView()
                .environmentObject(monitor)
                .frame(width: 380, height: 420)
        }
        .menuBarExtraStyle(.window)
    }
}
