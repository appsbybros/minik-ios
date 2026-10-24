import Foundation

// java.lang.System and android.os.SystemClock clocks (DESIGN 2.4, CORE-API "AClock.swift").
//
// Android's System.nanoTime() and SystemClock.uptimeMillis() read one clock, CLOCK_MONOTONIC: it starts at boot
// and stops while the device sleeps. The iOS equivalent is CLOCK_UPTIME_RAW, the Mach absolute clock. It is also
// the time base of CACurrentMediaTime() and of CADisplayLink timestamps, so Choreographer frame times, Handler
// message deadlines and the game's own nanoTime() deadlines compare directly, as on Android. The values are large
// (time since boot), so game code that uses 0 as an "expired" sentinel keeps working.
// Privacy manifest: these are "system boot time" clocks (NSPrivacyAccessedAPICategorySystemBootTime, reason 35F9.1).

/// java.lang.System clocks.
enum ASystem {
    /// `System.nanoTime()`: monotonic nanoseconds since boot, excluding sleep (CLOCK_UPTIME_RAW).
    static func nanoTime() -> Int64 {
        if let fake = AFakeClock.nanos {
            return fake
        }
        return Int64(truncatingIfNeeded: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
    }

    /// `System.currentTimeMillis()`: wall-clock milliseconds since 1970-01-01 UTC, truncated like Java.
    static func currentTimeMillis() -> Int64 {
        if let fake = AFakeClock.wallMillis {
            return fake
        }
        return Int64(truncatingIfNeeded: clock_gettime_nsec_np(CLOCK_REALTIME) / 1_000_000)
    }
}

/// android.os.SystemClock.
enum ASystemClock {
    /// `SystemClock.uptimeMillis()`: the System.nanoTime() clock in milliseconds (Android reads the same
    /// CLOCK_MONOTONIC for both). Handler message times and Choreographer callback due times use it.
    static func uptimeMillis() -> Int64 {
        return ASystem.nanoTime() / 1_000_000
    }

    /// `SystemClock.uptimeNanos()`.
    static func uptimeNanos() -> Int64 {
        return ASystem.nanoTime()
    }

    /// `SystemClock.elapsedRealtime()`: milliseconds since boot including sleep (Android CLOCK_BOOTTIME).
    static func elapsedRealtime() -> Int64 {
        return elapsedRealtimeNanos() / 1_000_000
    }

    /// `SystemClock.elapsedRealtimeNanos()`. Darwin's CLOCK_MONOTONIC_RAW is the continuous Mach clock: the
    /// CLOCK_UPTIME_RAW clock plus the time asleep, at the same tick rate. So, as on Android (CLOCK_BOOTTIME =
    /// CLOCK_MONOTONIC + sleep), elapsedRealtime() never falls behind uptimeMillis() and both advance together while
    /// awake. (Darwin's plain CLOCK_MONOTONIC is wall time minus boot time: microseconds, NTP-slewed, so on a device
    /// that never sleeps it can drift below the uptime clock.)
    static func elapsedRealtimeNanos() -> Int64 {
        if let fake = AFakeClock.nanos {
            return fake &+ AFakeClock.sleptNanos
        }
        return Int64(truncatingIfNeeded: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW))
    }

    /// `SystemClock.currentThreadTimeMillis()`: CPU time of the calling thread.
    static func currentThreadTimeMillis() -> Int64 {
        return Int64(truncatingIfNeeded: clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) / 1_000_000)
    }
}

/// Test hook: a manual clock behind ASystem and ASystemClock, and therefore behind AHandler, AChoreographer and the
/// animators. Only unit tests install it (through `AndroidKitTestLoop`); production code never does. While it is
/// installed the main looper's run-loop timer and the display link stay idle.
enum AFakeClock {
    /// The fake System.nanoTime() / SystemClock.uptimeNanos() value, or nil when the real clocks are used.
    nonisolated(unsafe) static var nanos: Int64? = nil
    /// Simulated device sleep: elapsedRealtimeNanos() = nanos + sleptNanos.
    nonisolated(unsafe) static var sleptNanos: Int64 = 0
    nonisolated(unsafe) private static var wallAtInstallMillis: Int64 = 0
    nonisolated(unsafe) private static var nanosAtInstall: Int64 = 0

    static var isInstalled: Bool {
        return nanos != nil
    }

    /// The fake System.currentTimeMillis(): the install-time wall clock moved forward with `nanos`.
    static var wallMillis: Int64? {
        guard let now = nanos else { return nil }
        return wallAtInstallMillis &+ (now &- nanosAtInstall) / 1_000_000
    }

    static func install(nanos start: Int64, wallMillis wall: Int64 = 1_760_000_000_000) {
        nanos = start
        nanosAtInstall = start
        wallAtInstallMillis = wall
        sleptNanos = 0
    }

    static func uninstall() {
        nanos = nil
        sleptNanos = 0
    }

    /// Moves the fake clocks forward.
    static func advance(byNanos delta: Int64) {
        guard let current = nanos else { return }
        nanos = current &+ delta
    }
}
