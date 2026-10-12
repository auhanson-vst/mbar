import Darwin
import Dispatch
import Foundation
import os

/// Always-on, low-overhead performance telemetry for mbar.
///
/// Background: mbar intermittently becomes slow to reveal/rebuild. The main
/// suspects are synchronous Accessibility (AX) calls, `CGWindowListCopyWindowInfo`,
/// and the `/bin/ps` activity sampler, all of which can run on the main thread
/// (directly inside `TaskbarController.rebuild()`), where any stall is
/// immediately visible to the user. A single unresponsive target app can make
/// an AX call block for seconds with no indication of why.
///
/// This file adds three things, all logged to both unified logging (`log
/// stream --predicate 'subsystem == "dev.auhanson.mbar"'`) and a plain text
/// file at `~/Library/Logs/mbar/perf.log` so a slowdown can be diagnosed
/// after the fact without attaching a profiler up front:
///
/// 1. `Telemetry.time` - wraps an operation, records an os_signpost interval
///    (visible in Instruments regardless of duration) and logs a warning
///    whenever it exceeds `slowThresholdSeconds`.
/// 2. `HangWatchdog` - a background thread that pings the main queue on a
///    fixed interval and logs whenever the round trip is slow, reporting
///    whichever `Telemetry.time`-wrapped operation was running at the time.
/// 3. `ResourceSampler` - periodic self CPU/memory sampling so a slowdown can
///    be correlated with elevated resource usage over the same window.
enum Telemetry {
    static let subsystem = "dev.auhanson.mbar"
    static let logger = Logger(subsystem: subsystem, category: "perf")
    private static let signpostLog = OSLog(subsystem: subsystem, category: "perf")

    /// Any single operation slower than this is logged as a warning. Kept
    /// low (50ms) because a blocked AX/CGWindowList call on the main thread
    /// is directly user-visible as "mbar is slow" well before it reaches
    /// seconds.
    static let slowThresholdSeconds: TimeInterval = 0.05

    private static let fileLock = NSLock()
    private static let logFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/mbar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("perf.log")
    }()

    /// Tracks the single most-recently-started operation per calling thread
    /// context so the hang watchdog can report what was likely blocking the
    /// main thread. Guarded by a lock because `time()` can be called from
    /// background queues (badge refresh, icon loading) concurrently with the
    /// main thread.
    private final class CurrentOperationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var label = "idle"
        private var startedAt = DispatchTime.now()

        func set(_ newLabel: String) {
            lock.lock()
            label = newLabel
            startedAt = DispatchTime.now()
            lock.unlock()
        }

        func clear(_ expected: String) {
            lock.lock()
            if label == expected { label = "idle" }
            lock.unlock()
        }

        func snapshot() -> (label: String, runningForSeconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000_000
            return (label, elapsed)
        }
    }

    private static let currentOperation = CurrentOperationBox()

    static func currentOperationSnapshot() -> (label: String, runningForSeconds: TimeInterval) {
        currentOperation.snapshot()
    }

    /// Times a synchronous operation. Always emits an os_signpost interval
    /// (so Instruments shows every call regardless of duration); logs a
    /// warning to unified logging + perf.log only when the call exceeds
    /// `slowThresholdSeconds`, to avoid spamming the log on the hot path.
    @discardableResult
    static func time<T>(_ label: String, extra: @autoclosure () -> String = "", _ body: () throws -> T) rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "operation", signpostID: signpostID, "%{public}s", label)
        currentOperation.set(label)
        let start = DispatchTime.now()
        defer {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            os_signpost(.end, log: signpostLog, name: "operation", signpostID: signpostID, "%.1fms", elapsed * 1000)
            currentOperation.clear(label)
            if elapsed >= slowThresholdSeconds {
                let extraInfo = extra()
                let suffix = extraInfo.isEmpty ? "" : " (\(extraInfo))"
                let ms = Int(elapsed * 1000)
                logger.warning("SLOW \(label, privacy: .public): \(ms)ms\(suffix, privacy: .public)")
                write("SLOW \(label): \(ms)ms\(suffix)")
            }
        }
        return try body()
    }

    /// Logs an informational line to both unified logging and perf.log,
    /// unconditionally (used for hang reports and periodic resource
    /// samples, which are already rate-limited by their own interval).
    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        write(message)
    }

    private static func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        fileLock.lock()
        defer { fileLock.unlock() }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logFileURL)
        }
    }
}

/// Detects main-thread stalls by pinging the main queue from a dedicated
/// background timer on a fixed interval and measuring how long the ping
/// takes to actually run. A healthy main run loop answers in low
/// milliseconds; a stall (e.g. a blocked AX call inside `rebuild()`) shows up
/// directly as elapsed time here, with `Telemetry.currentOperationSnapshot()`
/// reporting the operation that was most likely the cause.
final class HangWatchdog: @unchecked Sendable {
    static let shared = HangWatchdog()

    private let pingInterval: TimeInterval = 1.0
    private let hangThreshold: TimeInterval = 0.25
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "dev.auhanson.mbar.hangwatchdog")

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        source.setEventHandler { [weak self] in
            self?.ping()
        }
        source.resume()
        timer = source
    }

    private func ping() {
        let sentAt = DispatchTime.now()
        DispatchQueue.main.async {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - sentAt.uptimeNanoseconds) / 1_000_000_000
            guard elapsed >= self.hangThreshold else { return }
            let (op, runningFor) = Telemetry.currentOperationSnapshot()
            Telemetry.note(
                "MAIN THREAD HANG: \(Int(elapsed * 1000))ms since ping was scheduled; "
                    + "likely cause=\(op) running_for=\(Int(runningFor * 1000))ms"
            )
        }
    }
}

/// Periodically samples mbar's own CPU and memory usage so a reported
/// slowdown can be correlated with elevated self resource usage (e.g. a slow
/// memory leak, or CPU pegged by a runaway rebuild loop) rather than a
/// one-off blocking call.
final class ResourceSampler: @unchecked Sendable {
    static let shared = ResourceSampler()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "dev.auhanson.mbar.resourcesampler")
    private var lastCPUSeconds: Double?
    private var lastSampleAt: DispatchTime?

    func start(interval: TimeInterval = 30) {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler { [weak self] in
            self?.sample()
        }
        source.resume()
        timer = source
    }

    private func sample() {
        let (cpuSeconds, memoryMB) = Self.selfUsage()
        let now = DispatchTime.now()
        defer {
            lastCPUSeconds = cpuSeconds
            lastSampleAt = now
        }
        guard let lastCPUSeconds, let lastSampleAt else {
            Telemetry.note("RESOURCE SAMPLE: cpu_total=\(String(format: "%.1f", cpuSeconds))s peak_mem=\(memoryMB)MB")
            return
        }
        let wallElapsed = Double(now.uptimeNanoseconds - lastSampleAt.uptimeNanoseconds) / 1_000_000_000
        let cpuDelta = cpuSeconds - lastCPUSeconds
        let cpuPercent = wallElapsed > 0 ? (cpuDelta / wallElapsed) * 100 : 0
        Telemetry.note("RESOURCE SAMPLE: cpu=\(String(format: "%.1f", cpuPercent))% peak_mem=\(memoryMB)MB")
    }

    /// Returns (total user+system CPU seconds consumed since launch, peak
    /// resident memory in MB). Uses `getrusage` rather than Mach task_info
    /// calls to avoid the unsafe-pointer ceremony those require; `ru_maxrss`
    /// is reported in bytes on Darwin.
    private static func selfUsage() -> (cpuSeconds: Double, peakMemoryMB: Int) {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let userSeconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let systemSeconds = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        let peakMemoryMB = Int(usage.ru_maxrss / (1024 * 1024))
        return (userSeconds + systemSeconds, peakMemoryMB)
    }
}
