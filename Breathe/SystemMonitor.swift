//
//  SystemMonitor.swift
//  Breathe
//
//  Created by samuel Borg on 09/06/2026.
//

import Foundation
import Foundation
import Combine
import OSLog

class SystemMonitor: ObservableObject {
    @Published var totalCPUPercent: Double = 0.0
    @Published var totalMemoryPercent: Double = 0.0
    @Published var totalMemoryUsedMB: Double = 0.0
    @Published var totalMemoryMB: Double = 16000.0 // Default fallback
    @Published var processes: [AppProcess] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.breathe.monitor", category: "Engine")
    
    // System-defined names that shouldn't be casually killed by a user
    private let systemProcessNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow",
        "sysmond", "mds", "mds_stores", "coreaudiod", "Finder"
    ]

    init() {
        calculateTotalRAM()
        
        // Background timer running every 5 seconds
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMetrics()
            }
            .store(in: &cancellables)
            
        // Initial manual update
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
        process.launchPath = launchPath
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe() // Silence stderr diagnostics
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            logger.warning("Shell execution failed for \(launchPath)")
            return ""
        }
    }
    
    private func getSystemCPU() -> Double {
        // Fallback calculation via top snapshot
        let output = runShell("/usr/bin/top", ["-l", "1", "-s", "0", "-n", "0"])
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines where line.contains("CPU usage:") {
            let components = line.components(separatedBy: CharacterSet.whitespaces.inverted)
            let doubles = components.compactMap { Double($0) }
            if doubles.count >= 3 {
                // top returns: user%, sys%, idle%. Total active is 100 - idle
                let idle = doubles.last ?? 100.0
                return max(0.0, min(100.0, 100.0 - idle))
            }
        }
        return 0.0
    }
    
    private func getSystemMemory() -> (used: Double, percent: Double) {
        let output = runShell("/usr/bin/vm_stat", [])
        let lines = output.components(separatedBy: .newlines)
        
        var activePages: Double = 0
        var speculativePages: Double = 0
        var wiredPages: Double = 0
        var compressedPages: Double = 0
        
        // M2 Apple Silicon Macs explicitly utilize 16384 byte pages
        let pageSizeBytes: Double = 16384.0
        
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
        // Collect top metrics cleanly sorted by CPU
        let output = runShell("/bin/ps", ["-arcwwwxo", "pid,pcpu,pmem,rss,comm"])
        var lines = output.components(separatedBy: .newlines)
        
        if !lines.isEmpty { lines.removeFirst() } // Clean out header labels
        
        var parsedProcesses: [AppProcess] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Limit text processing parsing array safely around arbitrary user spaces
            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard components.count >= 5 else { continue }
            
            guard let pid = Int32(components[0]),
                  let cpu = Double(components[1]),
                  let rssKB = Double(components[3]) else { continue }
            
            // Everything else down the row belongs to the process command path
            let fullPath = components[4...].joined(separator: " ")
            let name = URL(fileURLWithPath: fullPath).lastPathComponent
            
            let memoryMB = rssKB / 1024.0
            
            // Safety flags to screen background core processes
            let isSystem = fullPath.hasPrefix("/") ||
                           systemProcessNames.contains(name) ||
                           fullPath.contains(":")
            
            let processItem = AppProcess(
                id: pid,
                name: name,
                cpuUsage: cpu,
                memoryUsageMB: memoryMB,
                isSystemProcess: isSystem
            )
            parsedProcesses.append(processItem)
            
            if parsedProcesses.count >= 15 { break } // Keep UI list lightweight
        }
        
        return parsedProcesses
    }
    
    func terminateProcess(pid: Int32) {
        // Standard Unix utility pipeline execution
        let result = kill(pid, SIGTERM)
        if result != 0 {
            logger.error("Failed to terminate process with PID: \(pid)")
        }
        refreshMetrics()
    }
}
