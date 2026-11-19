import Foundation
#if canImport(FirebaseDatabase)
import FirebaseDatabase
#endif

/// Android `LagDiagnostics`: an explicit ten-minute opt-in. Aggregate timings only: no names, room codes, input
/// traces or images. Uploaded to `minikAmudu/diagnostics/{uid}/{session}` with Android's field names; the rules
/// reject unknown fields, so Android's `android` (SDK level) field is left out on iOS and `model` is "Apple" plus the
/// hardware identifier.
@MainActor enum LagDiagnostics {
    private static var until: Int64 = 0
    private static var session = ""
    private static var started: Int64 = 0
    private static var lastUpload: Int64 = 0
    private static var uploadedEnd = false
    private static var frames: Int64 = 0
    private static var frameTotal: Int64 = 0
    private static var frameMax: Int64 = 0
    private static var over50: Int64 = 0
    private static var snapshots: Int64 = 0
    private static var gapTotal: Int64 = 0
    private static var gapMax: Int64 = 0
    private static var gapsOver250: Int64 = 0
    private static var previousSnapshot: Int64 = 0
    private static var ageTotal: Int64 = 0
    private static var ageMax: Int64 = 0
    private static var acks: Int64 = 0
    private static var ackTotal: Int64 = 0
    private static var ackMax: Int64 = 0
    private static var commands: Int64 = 0
    private static var commandAckTotal: Int64 = 0
    private static var commandAckMax: Int64 = 0
    private static var sentBytes: Int64 = 0
    private static var receivedBytes: Int64 = 0
    private static var failures: Int64 = 0
    private static var lastError = ""
    private static var processingCount: Int64 = 0
    private static var processingTotal: Int64 = 0
    private static var processingMax: Int64 = 0
    private static var uploading = false
    private static var expire: DispatchWorkItem?
    private static var account = ""
    private static var hostRole = false
    #if canImport(FirebaseDatabase)
    private static var root: DatabaseReference?
    #endif

    /// Android `System.currentTimeMillis()`.
    private static func wallMs() -> Int64 { return Int64(Date().timeIntervalSince1970 * 1000) }

    static var active: Bool { return wallMs() < until }

    /// Kotlin `session.take(8)`.
    static var id: String { return String(session.prefix(8)) }

    static func start() {
        expire?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { LagDiagnostics.stop() } }
        expire = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: item)
        #if canImport(FirebaseDatabase)
        root = nil
        #endif
        account = ""
        started = wallMs()
        until = started + 600_000
        session = UUID().uuidString.lowercased()
        lastUpload = 0
        uploadedEnd = false
        uploading = false
        processingCount = 0; processingTotal = 0; processingMax = 0
        frames = 0; frameTotal = 0; frameMax = 0; over50 = 0; snapshots = 0; gapTotal = 0; gapMax = 0; gapsOver250 = 0
        previousSnapshot = 0; ageTotal = 0; ageMax = 0
        acks = 0; ackTotal = 0; ackMax = 0; commands = 0; commandAckTotal = 0; commandAckMax = 0
        sentBytes = 0; receivedBytes = 0; failures = 0; lastError = ""
    }

    static func stop() {
        until = 0
        expire?.cancel()
        expire = nil
        #if canImport(FirebaseDatabase)
        if let r = root { upload(r, uid: account, host: hostRole) }
        #endif
    }

    static func frame(_ ms: Int64) {
        if !active { return }
        frames += 1
        frameTotal += ms
        frameMax = max(frameMax, ms)
        if ms > 50 { over50 += 1 }
    }

    static func snapshot(_ state: Node, _ serverNow: Int64) {
        if !active { return }
        let now = uptimeMs()
        if previousSnapshot > 0 {
            let gap = now - previousSnapshot
            gapTotal += gap
            gapMax = max(gapMax, gap)
            if gap > 250 { gapsOver250 += 1 }
        }
        previousSnapshot = now
        snapshots += 1
        let age = max(serverNow - Kotlin.toLong(state.num("publishedAt", Double(serverNow))), 0)
        ageTotal += age
        ageMax = max(ageMax, age)
        receivedBytes += bytes(state)
    }

    static func sending(_ update: [String: Any]) {
        if active { sentBytes += bytes(update) }
    }

    static func ack(_ ms: Int64, command: Bool = false) {
        if !active { return }
        if command {
            commands += 1
            commandAckTotal += ms
            commandAckMax = max(commandAckMax, ms)
        } else {
            acks += 1
            ackTotal += ms
            ackMax = max(ackMax, ms)
        }
    }

    static func processing(_ microseconds: Int64) {
        if active {
            processingCount += 1
            processingTotal += microseconds
            processingMax = max(processingMax, microseconds)
        }
    }

    static func error(_ category: String) {
        if active {
            failures += 1
            lastError = String(category.prefix(48))
        }
    }

    /// Local QA summary; keep the deployed Firebase schema unchanged.
    static func processingSummary() -> [String: Any] {
        return ["clientProcessingSamples": processingCount,
                "clientProcessingMeanUs": processingCount > 0 ? Double(processingTotal) / Double(processingCount) : 0.0,
                "clientProcessingMaxUs": processingMax]
    }

    /// Kotlin `JSONObject(map).toString().toByteArray(UTF_8).size`.
    private static func bytes(_ value: [String: Any]) -> Int64 {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return 0 }
        return Int64(data.count)
    }

    private static func mean(_ total: Int64, _ count: Int64) -> Double {
        return count > 0 ? Double(total) / Double(count) : 0.0
    }

    /// Android `Build.MANUFACTURER + " " + Build.MODEL`.
    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw -> String in
            let bytes = raw.prefix(while: { $0 != 0 })
            return String(decoding: bytes, as: UTF8.self)
        }
        return String(("Apple " + machine).prefix(90))
    }

    #if canImport(FirebaseDatabase)
    static func upload(_ dbRoot: DatabaseReference, uid: String, host: Bool) {
        if Kotlin.isBlank(session) || Kotlin.isBlank(uid) { return }
        root = dbRoot
        account = uid
        hostRole = host
        if uploading || uploadedEnd { return }
        let now = wallMs()
        if active && now - lastUpload < 15000 { return }
        lastUpload = now
        uploading = true
        let info = Bundle.main.infoDictionary ?? [:]
        let payload: [String: Any] = [
            "version": (info["CFBundleShortVersionString"] as? String) ?? "",
            "code": Int((info["CFBundleVersion"] as? String) ?? "") ?? 0,
            "model": deviceModel(),
            "language": AppText.language, "role": host ? "host" : "guest", "startedAt": started, "updatedAt": now,
            "expiresAt": now + 86_400_000, "completed": !active,
            "frameCount": frames, "frameMeanMs": mean(frameTotal, frames), "frameMaxMs": frameMax, "framesOver50Ms": over50,
            "snapshotCount": snapshots, "snapshotGapMeanMs": mean(gapTotal, max(snapshots - 1, 0)), "snapshotGapMaxMs": gapMax,
            "gapsOver250Ms": gapsOver250,
            "snapshotAgeMeanMs": mean(ageTotal, snapshots), "snapshotAgeMaxMs": ageMax,
            "publishAckCount": acks, "publishAckMeanMs": mean(ackTotal, acks), "publishAckMaxMs": ackMax,
            "commandAckCount": commands, "commandAckMeanMs": mean(commandAckTotal, commands), "commandAckMaxMs": commandAckMax,
            "serializedSentBytes": sentBytes, "serializedReceivedBytes": receivedBytes, "failures": failures,
            "lastErrorCategory": lastError,
        ]
        let finished = !active
        let token = session
        dbRoot.child("minikAmudu/diagnostics/\(uid)/\(session)").setValue(payload) { error, _ in
            MainActor.assumeIsolated {
                if token != LagDiagnostics.session { return }
                LagDiagnostics.uploading = false
                if error == nil && finished { LagDiagnostics.uploadedEnd = true }
                if !LagDiagnostics.active && !finished { LagDiagnostics.upload(dbRoot, uid: uid, host: host) }
            }
        }
    }
    #endif
}
