import Foundation
import AppKit
import Darwin

@main struct IdleMonitorTests {
    @MainActor static func main() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let store = try ClipStore(inMemory: true, monitor: true, pasteboard: board)
        try await Task.sleep(for: .seconds(1))
        func cpu() -> Double { var t = timespec(); clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t); return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9 }
        let startCPU = cpu(); let start = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(for: .seconds(30))
        let wall = ProcessInfo.processInfo.systemUptime - start; let cpuTime = cpu() - startCPU
        precondition(store.items.isEmpty && !store.processing && !store.reading)
        print(String(format: "Idle capture monitor: %.1fs wall, %.4fs CPU, %.3f%% of one core. Named empty clipboard; not a macOS Energy Impact measurement.", wall, cpuTime, cpuTime / wall * 100))
    }
}
