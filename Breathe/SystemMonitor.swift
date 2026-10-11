//
//  SystemMonitor.swift
//  Breathe
//
//  Copyright © 2026 Studio 12. Released under the MIT License.
//

import Foundation
import Combine
import OSLog

class SystemMonitor: ObservableObject {
    @Published var totalCPUPercent: Double = 0.0
    @Published var totalMemoryPercent: Double = 0.0
    @Published var totalMemoryUsedMB: Double = 0.0
    @Published var totalMemoryMB: Double = 16000.0 // Default fallback until measured
    @Published var processes: [AppProcess] = []

    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.studio12.breathe", category: "Engine")
    private let currentUser = NSUserName()

    // Critical processes that should never show a Quit button.
    private let systemProcessNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow",
        "sysmond", "mds", "mds_stores", "coreaudiod", "Finder"
    ]

    init() {
        calculateTotalRAM()

        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshMetrics() }
            .store(in: &cancellables)

        refreshMetrics()
    }

    private func calculateTotalRAM() {
        var memSize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &memSize, &size, nil, 0) == 0 {
            self.totalMemoryMB = Double(memSize) / (1024.0 * 1024.0)
        }
    }

    func refreshMetrics() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let cpu = self.getSystemCPU()
            let (memUsed, memPercent) = self.getSystemMemory()
            let processList = self.getTopProcesses()

            DispatchQueue.main.async {
                self.totalCPUPercent = cpu
                self.totalMemoryUsedMB = memUsed
                self.totalMemoryPercent = memPercent
                self.processes = processList
            }
        }
    }

    private func runShell(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()

        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe() // Silence stderr diagnostics

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            logger.warning("Shell execution failed for \(launchPath)")
            return ""
        }
    }

    private func getSystemCPU() -> Double {
        // Two samples: first is a baseline, second reflects the real
        // interval delta. Parse the LAST "CPU usage:" line.
        let output = runShell("/usr/bin/top", ["-l", "2", "-s", "0", "-n", "0"])
        let lines = output.components(separatedBy: .newlines)

        var lastIdle: Double? = nil
        for line in lines where line.contains("CPU usage:") {
            // e.g. "CPU usage: 4.76% user, 9.52% sys, 85.71% idle"
            let doubles = line
                .components(separatedBy: CharacterSet(charactersIn: "%, "))
                .compactMap { Double($0) }
            if let idle = doubles.last { lastIdle = idle }
        }
        if let idle = lastIdle {
            return max(0.0, min(100.0, 100.0 - idle))
        }
        return 0.0
    }

    private func pageSize(from vmStatOutput: String) -> Double {
        // Header: "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
        if let header = vmStatOutput.components(separatedBy: .newlines).first {
            let digits = header
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Double($0) }
            if let size = digits.first, size > 0 { return size }
        }
        return 16384.0 // Apple Silicon default
    }

    private func getSystemMemory() -> (used: Double, percent: Double) {
        let output = runShell("/usr/bin/vm_stat", [])
        let lines = output.components(separatedBy: .newlines)

        var activePages: Double = 0
        var speculativePages: Double = 0
        var wiredPages: Double = 0
        var compressedPages: Double = 0

        let pageSizeBytes = pageSize(from: output)

        for line in lines {
            let cleanLine = line.replacingOccurrences(of: ".", with: "")
            let parts = cleanLine.components(separatedBy: ":")
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0

                if key.contains("Pages active") { activePages = value }
                else if key.contains("Pages speculative") { speculativePages = value }
                else if key.contains("Pages wired") { wiredPages = value }
                else if key.contains("Pages occupied by compressor") { compressedPages = value }
            }
        }

        let totalPagesUsed = activePages + speculativePages + wiredPages + compressedPages
        let usedMB = (totalPagesUsed * pageSizeBytes) / (1024.0 * 1024.0)
        let percent = (usedMB / totalMemoryMB) * 100.0

        return (usedMB, max(0.0, min(100.0, percent)))
    }

    private func getTopProcesses() -> [AppProcess] {
        // Sorted by CPU, all users, wide output.
        // Columns: pid, %cpu, %mem, rss(KB), user, executable path
        let output = runShell("/bin/ps", ["-arwwwxo", "pid,pcpu,pmem,rss,user,comm"])
        var lines = output.components(separatedBy: .newlines)
        if !lines.isEmpty { lines.removeFirst() } // Drop header row

        var parsed: [AppProcess] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard components.count >= 6 else { continue }

            guard let pid = Int32(components[0]),
                  let cpu = Double(components[1]),
                  let rssKB = Double(components[3]) else { continue }

            let owner = components[4]
            let fullPath = components[5...].joined(separator: " ")
            let name = URL(fileURLWithPath: fullPath).lastPathComponent
            let memoryMB = rssKB / 1024.0

            // Only our own processes are safely killable.
            let isSystem = owner != currentUser || systemProcessNames.contains(name)

            parsed.append(
                AppProcess(id: pid, name: name, cpuUsage: cpu,
                           memoryUsageMB: memoryMB, isSystemProcess: isSystem)
            )

            if parsed.count >= 15 { break } // Keep the UI list light
        }

        return parsed
    }

    func terminateProcess(pid: Int32) {
        let result = kill(pid, SIGTERM)
        if result != 0 {
            logger.error("Failed to terminate PID \(pid): errno \(errno)")
        }
        refreshMetrics()
    }
}
