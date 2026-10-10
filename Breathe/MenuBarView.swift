//
//  MenuBarView.swift
//  Breathe
//
//  Copyright © 2026 Studio 12. All rights reserved.
//

import Foundation
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Breathe").font(.headline).fontWeight(.bold)
                Spacer()
                Text("System Status").font(.caption).foregroundColor(.secondary)
            }

            Divider()

            VStack(spacing: 12) {
                MetricBar(
                    label: "Processor",
                    percentage: monitor.totalCPUPercent,
                    description: String(format: "%.1f%% Active", monitor.totalCPUPercent)
                )
                MetricBar(
                    label: "Memory",
                    percentage: monitor.totalMemoryPercent,
                    description: String(format: "%.1f GB of %.0f GB", monitor.totalMemoryUsedMB / 1024.0, monitor.totalMemoryMB / 1024.0)
                )
            }

            Divider()

            Text("Active Tasks").font(.subheadline).fontWeight(.semibold)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(monitor.processes) { process in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(process.name).font(.body).lineLimit(1)
                                Text(String(format: "CPU: %.1f%%  •  RAM: %.0f MB", process.cpuUsage, process.memoryUsageMB))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if !process.isSystemProcess {
                                Button(action: { monitor.terminateProcess(pid: process.id) }) {
                                    Text("Quit").font(.caption)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(16)
        .frame(width: 380)
    }
}

struct MetricBar: View {
    let label: String
    let percentage: Double
    let description: String

    private var statusColor: Color {
        if percentage >= 80.0 { return .red }
        if percentage >= 60.0 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.body)
                Spacer()
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            ProgressView(value: min(100.0, max(0.0, percentage)), total: 100.0)
                .progressViewStyle(.linear)
                .tint(statusColor)
        }
    }
}
