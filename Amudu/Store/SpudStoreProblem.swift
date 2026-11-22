import Foundation
import Network
import StoreKit

/// iOS payment model (CLAUDE.md): why the full game cannot be bought right now, so the unlock screen says what really
/// happened (bug report 2026-11-22, 2.2; the same fix as Minik Plus's `MinikStoreProblem`). Before, every failure read
/// "The App Store cannot be reached right now. Check the connection", also when the device was online and the App
/// Store simply answered without the product.
enum SpudStoreProblem: Equatable, Sendable {
    /// The device has no internet connection.
    case offline
    /// Online, but the App Store did not answer in time or answered with an error.
    case notAnswering
    /// The App Store answered, but without the full-game product (not yet approved, or not sold in this storefront).
    case productUnavailable
    /// In-app purchases are turned off on this device (Screen Time).
    case purchasesNotAllowed
}

/// Whether the device has a network path now. Only used to word a store failure.
final class SpudNetworkStatus: @unchecked Sendable {
    static let shared = SpudNetworkStatus()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var isSatisfied: Bool?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "spud.network-status"))
    }

    /// True only when the device is known to be offline (no Wi-Fi or mobile data).
    var isOffline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSatisfied == false
    }

    /// Screen Time can turn in-app purchases off.
    static var canMakePayments: Bool {
        return AppStore.canMakePayments
    }

    private func update(_ satisfied: Bool) {
        lock.lock()
        isSatisfied = satisfied
        lock.unlock()
    }
}

/// Gives an App Store request a time limit, so the unlock screen never waits forever on "Loading…".
enum SpudStoreDeadline {
    struct Expired: Error, Equatable {}

    static func value<T: Sendable>(within timeout: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let once = SpudResumeOnce()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let work = Task {
                do {
                    let value = try await operation()
                    if once.claim() { continuation.resume(returning: value) }
                } catch {
                    if once.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if once.claim() {
                    work.cancel()
                    continuation.resume(throwing: Expired())
                }
            }
        }
    }
}

/// Lets exactly one of two racing tasks resume a continuation.
private final class SpudResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}
