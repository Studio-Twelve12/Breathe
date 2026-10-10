//
//  ProcessInfo.swift
//  Breathe
//
//  Created by samuel Borg on 09/06/2026.
//

import Foundation
import Foundation

struct AppProcess: Identifiable, Equatable {
    let id: Int32          // Process ID (PID)
    let name: String
    let cpuUsage: Double   // Percentage (0.0 - 100.0+)
    let memoryUsageMB: Double
    let isSystemProcess: Bool
}
