import Foundation
import os

/// android.util.Log (DESIGN 2.4): the same calls, written to the unified log (Console.app, category = tag) in
/// DEBUG builds only. Release builds log nothing.
enum ALog {
    static let VERBOSE = 2
    static let DEBUG = 3
    static let INFO = 4
    static let WARN = 5
    static let ERROR = 6
    static let ASSERT = 7

    static func v(_ tag: String, _ msg: String, _ error: Error? = nil) {
        println(VERBOSE, tag, msg, error)
    }

    static func d(_ tag: String, _ msg: String, _ error: Error? = nil) {
        println(DEBUG, tag, msg, error)
    }

    static func i(_ tag: String, _ msg: String, _ error: Error? = nil) {
        println(INFO, tag, msg, error)
    }

    static func w(_ tag: String, _ msg: String, _ error: Error? = nil) {
        println(WARN, tag, msg, error)
    }

    static func e(_ tag: String, _ msg: String, _ error: Error? = nil) {
        println(ERROR, tag, msg, error)
    }

    static func wtf(_ tag: String, _ msg: String, _ error: Error? = nil) {
        println(ASSERT, tag, msg, error)
    }

    /// `Log.isLoggable`: Android's default level for every tag is INFO.
    static func isLoggable(_ tag: String, _ level: Int) -> Bool {
        return level >= INFO
    }

    /// `Log.getStackTraceString(throwable)`.
    static func getStackTraceString(_ error: Error?) -> String {
        guard let error = error else { return "" }
        return String(describing: error)
    }

    #if DEBUG
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.appsbybros.minik.swish"
    /// One os.Logger per tag (logging may come from the texture worker thread, hence the lock).
    private static let loggersLock = NSLock()
    nonisolated(unsafe) private static var loggers: [String: os.Logger] = [:]

    private static func logger(_ tag: String) -> os.Logger {
        loggersLock.lock()
        defer { loggersLock.unlock() }
        if let cached = loggers[tag] {
            return cached
        }
        let created = os.Logger(subsystem: subsystem, category: tag)
        loggers[tag] = created
        return created
    }
    #endif

    /// Like Log.println_native: the message, then a newline and the throwable's description when one is given.
    private static func println(_ priority: Int, _ tag: String, _ msg: String, _ error: Error?) {
        #if DEBUG
        var text = msg
        if let error = error {
            text += "\n" + getStackTraceString(error)
        }
        let log = logger(tag)
        switch priority {
        case VERBOSE, DEBUG:
            log.debug("\(text, privacy: .public)")
        case INFO:
            log.info("\(text, privacy: .public)")
        case WARN:
            log.warning("\(text, privacy: .public)")
        case ERROR:
            log.error("\(text, privacy: .public)")
        default:
            log.fault("\(text, privacy: .public)")
        }
        #endif
    }
}
