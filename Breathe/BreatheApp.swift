//
//  BreatheApp.swift
//  Breathe
//
//  Created by samuel Borg on 09/06/2026.
//

import SwiftUI

@main
struct BreatheApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        // Adding an explicit title string alongside the icon forces macOS
        // to allocate proper tracking width in the system menu bar.
        MenuBarExtra("Breathe", systemImage: "wind") {
            MenuBarView()
                .environmentObject(monitor)
                .frame(width: 380, height: 420)
        }
        .menuBarExtraStyle(.window)
    }
}

