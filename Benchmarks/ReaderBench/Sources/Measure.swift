import Darwin
import Foundation

/// Clock and process probes shared by every scenario.
enum Measure {
    /// Milliseconds elapsed while `body` runs.
    @MainActor
    static func time<T>(_ body: () async throws -> T) async rethrows -> (T, Double) {
        let start = ContinuousClock.now
        let value = try await body()
        return (value, milliseconds(since: start))
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        milliseconds(from: start, to: .now)
    }

    static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let elapsed = end - start
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// The app's physical footprint in megabytes, the figure Xcode's memory
    /// gauge and jetsam use. WebKit content runs in separate processes, so
    /// this undercounts web-based readers; the report says so.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// Number of threads in the app process. PDFKit's page analysis on
    /// iOS 26 has been reported to leak threads, so this is tracked.
    static func threadCount() -> Int {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return -1 }
        for index in 0..<Int(count) {
            mach_port_deallocate(mach_task_self_, threads[index])
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threads)),
            vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)
        )
        return Int(count)
    }

    /// Lets the run loop settle, so work queued by the previous step
    /// (layout, tile rendering, deferred releases) doesn't land in the next.
    @MainActor
    static func settle(_ seconds: Double = 0.5) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// Waits for a callback with a timeout, so a reader that never reports
/// readiness fails that sample instead of hanging the run.
@MainActor
final class Signal {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var fired = false
    private var generation = 0
    /// When the first `fire()` since the last `reset()` happened.
    private(set) var firedAt: ContinuousClock.Instant?

    func fire() {
        if firedAt == nil { firedAt = .now }
        fired = true
        continuation?.resume(returning: true)
        continuation = nil
    }

    func reset() {
        fired = false
        firedAt = nil
    }

    func wait(timeout seconds: Double = 30) async -> Bool {
        if fired { return true }
        generation += 1
        let waiting = generation
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                // A timer left over from an earlier wait must not end this one.
                if waiting == self.generation, let pending = self.continuation {
                    self.continuation = nil
                    pending.resume(returning: false)
                }
            }
        }
    }
}
