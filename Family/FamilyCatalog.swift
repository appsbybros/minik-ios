import Foundation

/// Port of Android MinikFamilyServices FamilyCatalog.java: the public editorial catalogue (no
/// sign-in, player IDs, device IDs or analytics). Refreshed at most daily from the public Realtime
/// Database endpoint; the last valid copy is kept offline and the bundled copy is the fallback.
struct FamilyCatalog {
    static let endpoint = "https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/familyApps/catalog.json"
    static let directory = "https://miniklearn.com/apps/index.html"
    static let day: TimeInterval = 86_400

    let version: Int
    let enabled: Bool
    let entries: [Entry]

    struct Entry {
        let id: String
        let applicationId: String
        let landingUrl: String
        let playUrl: String
        let webUrl: String
        let iosUrl: String
        let artUrl: String
        let aliases: Set<String>
        let titles: [String: String]
        let bodies: [String: String]
        let assets: [String: String]
        let enabled: Bool
        let playAvailable: Bool
        let weight: Int

        init?(_ id: String, _ j: [String: Any]) {
            guard let application = j["applicationId"] as? String,
                  FamilyCatalog.matches(application, "[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+") else { return nil }
            self.id = id
            applicationId = application
            enabled = FamilyCatalog.bool(j["enabled"], true)
            weight = max(1, min(20, FamilyCatalog.int(j["weight"], 1)))
            playAvailable = FamilyCatalog.bool(j["playAvailable"], false)
            var names: Set<String> = [application]
            for alias in (j["aliases"] as? [Any]) ?? [] { names.insert(FamilyCatalog.string(alias)) }
            aliases = names
            titles = FamilyCatalog.translations(j["title"], 90)
            bodies = FamilyCatalog.translations(j["body"], 400)
            assets = FamilyCatalog.translations(j["artAsset"], 180)
            if titles["en"] == nil || bodies["en"] == nil { return nil }
            landingUrl = FamilyCatalog.safeLink(FamilyCatalog.string(j["landingUrl"]), ["miniklearn.com", "easycallandanswer.com"])
            webUrl = FamilyCatalog.safeLink(FamilyCatalog.string(j["webUrl"]), ["miniklearn.com", "easycallandanswer.com"])
            iosUrl = FamilyCatalog.safeLink(FamilyCatalog.string(j["iosUrl"]), ["apps.apple.com"])
            let play = FamilyCatalog.safeLink(FamilyCatalog.string(j["playUrl"]), ["play.google.com"])
            playUrl = play == "https://play.google.com/store/apps/details?id=" + application ? play : ""
            artUrl = FamilyCatalog.safeLink(FamilyCatalog.string(j["artUrl"]), ["miniklearn.com", "easycallandanswer.com"])
        }

        /// Android `isSelf(pkg)`: the host's own application ID, aliases and debug/QA builds.
        func isSelf(_ pkg: String) -> Bool {
            return aliases.contains { pkg == $0 || pkg.hasPrefix($0 + ".debug") || pkg.hasPrefix($0 + ".qa") }
        }

        func title(_ locale: String) -> String { return FamilyCatalog.localized(titles, locale) }
        func body(_ locale: String) -> String { return FamilyCatalog.localized(bodies, locale) }

        func asset(_ locale: String) -> String {
            let a = FamilyCatalog.localized(assets, locale)
            return FamilyCatalog.matches(a, "minik-family/art/[a-z0-9_-]+\\.(png|webp|jpg)") ? a : ""
        }
    }

    // MARK: org.json helpers

    /// Java `String.matches`: the pattern must match the whole value (a trailing newline too).
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        return value.range(of: "^(?:" + pattern + ")\\z", options: .regularExpression) != nil
    }

    private static func string(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return "\(value)"
    }

    private static func bool(_ value: Any?, _ fallback: Bool) -> Bool {
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
        if let s = value as? String {
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
        }
        return fallback
    }

    private static func int(_ value: Any?, _ fallback: Int) -> Int {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            let d = n.doubleValue
            return d.isFinite ? Int(max(min(d, 2_147_483_647), -2_147_483_648)) : fallback
        }
        if let s = value as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite {
            return Int(max(min(d, 2_147_483_647), -2_147_483_648))
        }
        return fallback
    }

    /// Android `localized(values, locale)`: the exact tag, then its language, then English.
    static func localized(_ values: [String: String], _ locale: String?) -> String {
        let key = (locale ?? "en").replacingOccurrences(of: "_", with: "-")
        if let value = values[key] { return value }
        let base = String(key.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        if let value = values[base] { return value }
        return values["en"] ?? ""
    }

    /// Android `translations(j, max)`: copy no longer than `max` UTF-16 units.
    static func translations(_ value: Any?, _ maximum: Int) -> [String: String] {
        var out: [String: String] = [:]
        guard let j = value as? [String: Any] else { return out }
        for (k, v) in j {
            let s = string(v)
            if s.utf16.count <= maximum { out[k] = s }
        }
        return out
    }

    /// Android `safeLink(raw, hosts)`: HTTPS on port 443 to an allowed host, without user info.
    static func safeLink(_ raw: String, _ hosts: [String]) -> String {
        guard let u = URLComponents(string: raw), let scheme = u.scheme, scheme.lowercased() == "https",
              u.user == nil, u.password == nil, u.port == nil || u.port == 443, let host = u.host else { return "" }
        return hosts.contains { $0.lowercased() == host.lowercased() } ? raw : ""
    }

    /// Android `parse(raw)`: schema 1, at most 100 entries, invalid entries skipped, sorted by key.
    static func parse(_ raw: String) -> FamilyCatalog? {
        guard let data = raw.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let schema = j["schema"] as? NSNumber, CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.intValue == 1,
              let apps = j["apps"] as? [String: Any], apps.count <= 100 else { return nil }
        var entries: [Entry] = []
        for (key, value) in apps where matches(key, "[a-z0-9_-]{1,60}") {
            if let item = value as? [String: Any], let entry = Entry(key, item) { entries.append(entry) }
        }
        entries.sort { Array($0.id.utf16).lexicographicallyPrecedes(Array($1.id.utf16)) }
        return FamilyCatalog(version: int(j["version"], 1), enabled: bool(j["enabled"], true), entries: entries)
    }

    /// Android `choose(ownPackage, random)`: weighted among enabled entries other than the host. iOS
    /// identifies the host by its catalogue key (Android compares package names and aliases).
    func choose(_ ownKey: String) -> Entry? {
        if !enabled { return nil }
        let allowed = entries.filter { $0.enabled && $0.id != ownKey }
        let total = allowed.reduce(0) { $0 + $1.weight }
        if total == 0 { return nil }
        var pick = Int.random(in: 0..<total)
        for e in allowed {
            pick -= e.weight
            if pick < 0 { return e }
        }
        return nil
    }

    // MARK: Storage (Android SharedPreferences "minik_family_messages")

    static func key(_ name: String) -> String { return "minik_family_messages." + name }

    /// Android `load(context)`: the cached catalogue, else the bundled one, else an empty, disabled one.
    static func load() -> FamilyCatalog {
        if let cached = UserDefaults.standard.string(forKey: key("catalogue")), !cached.isEmpty, let c = parse(cached) { return c }
        if let url = Bundle.main.url(forResource: "minik-family-catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url), data.count <= 250_000,
           let raw = String(data: data, encoding: .utf8), let c = parse(raw) { return c }
        return FamilyCatalog(version: 0, enabled: false, entries: [])
    }

    /// Android `refresh(context)`: at most once a day; a response is kept only when it parses.
    static func refresh() {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        if now - defaults.double(forKey: key("catalogueChecked")) < day { return }
        defaults.set(now, forKey: key("catalogueChecked"))
        guard let url = URL(string: endpoint) else { return }
        FamilyFetch.data(url, maximum: 250_000) { data in
            guard let data = data, let raw = String(data: data, encoding: .utf8), parse(raw) != nil else { return }
            UserDefaults.standard.set(raw, forKey: key("catalogue"))
        }
    }
}

/// Android `FamilyCatalog.fetch` and `read`: HTTPS GET with 6 s timeouts and no redirects; the body
/// is streamed and dropped as soon as it passes the size cap.
final class FamilyFetch: NSObject, URLSessionTaskDelegate {
    private static let delegate = FamilyFetch()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func data(_ url: URL, maximum: Int, _ completion: @escaping @Sendable (Data?) -> Void) {
        Task.detached(priority: .utility) { completion(await FamilyFetch.fetch(url, maximum: maximum)) }
    }

    private static func fetch(_ url: URL, maximum: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= Int64(maximum) else {
                bytes.task.cancel()
                return nil
            }
            var data = Data()
            for try await byte in bytes {
                if data.count == maximum {
                    // Android `read`: "Response too large".
                    bytes.task.cancel()
                    return nil
                }
                data.append(byte)
            }
            return data
        } catch {
            return nil
        }
    }
}
