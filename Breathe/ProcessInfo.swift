//
//  ProcessInfo.swift
//  Breathe
//
//  Copyright © 2026 Studio 12. Released under the MIT License.
//

import Foundation

/// A single running process surfaced in the Breathe panel.
struct AppProcess: Identifiable, Equatable {
    let id: Int32            // Process ID (PID)
    let name: String
    let cpuUsage: Double      // Percentage (0.0 - 100.0+)
    let memoryUsageMB: Double
    let isSystemProcess: Bool // true when owned by root/another user (not safely killable)
}
