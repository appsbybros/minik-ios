import Foundation

/// Android `OnlineErrors`: never present SDK paths, permission codes or English exception text to players.
enum OnlineErrors {
    /// Kotlin `error is IOException || "network"/"disconnected"/"unavailable" in error.message.lowercase()`. On iOS
    /// the transport errors (Android's `IOException`) are the URL and POSIX error domains, also as an underlying error.
    static func message(_ error: Error) -> String {
        let ns = error as NSError
        let text = ns.localizedDescription.lowercased()
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        let transport = [NSURLErrorDomain, NSPOSIXErrorDomain].contains(ns.domain) ||
            (underlying.map { [NSURLErrorDomain, NSPOSIXErrorDomain].contains($0.domain) } ?? false)
        if transport || text.contains("network") || text.contains("disconnected") || text.contains("unavailable") {
            return AppText.t("The connection is unavailable. Please reconnect and try again.", "אין חיבור כרגע. התחברו ונסו שוב.")
        }
        return AppText.t("This request could not be completed. Please try again.", "לא ניתן להשלים את הבקשה כרגע. נסו שוב.")
    }
}
