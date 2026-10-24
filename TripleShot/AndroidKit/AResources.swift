import CoreGraphics
import Foundation
import ImageIO
import UIKit
import os

// The Android resource runtime (CORE-API "AResources.swift + generated R.swift", DESIGN 2.5, 2.7 and 5).
//
// TripleShot/Res is a folder reference copied into the app bundle as Res/. Scripts/tripleshot-sync-resources.py
// writes it from the Android project (res/ and assets/, read only):
//   Res/strings/he.json         values/ (the default resources, Hebrew), resolved like aapt2
//   Res/strings/en.json         values-en/, each resource missing there taken from values/ like Android
//   Res/strings/android.json    the android.R.string texts the code uses, in every framework language
//   Res/drawable-sizes.json     file and pixel size of every bitmap drawable
//   Res/drawable-nodpi/, Res/drawable/, Res/raw/, Res/assets/question_banks/   the Android files, byte for byte
//                               (except raw Ogg Vorbis, which AVAudioFile cannot read: Res/raw/<name>.caf, ALAC)
//   Res/R.swift                 (compiled) R with the Android names; ids ARE the resource names
//
// Language (DESIGN 2.7): like Android's Resources, everything follows the configuration's first locale
// (`resources.configuration.locales[0]`, AConfiguration.locales = the first of Locale.preferredLanguages):
//   - the app strings: values-en/ when its language is "en", values/ (Hebrew) for every other language;
//   - the android.R strings: the framework's own translation for that language (English when it has none);
//   - the plural rules of getQuantityString: that locale's CLDR rules (KitResourcesPluralRules.swift);
//   - the String.format locale of getString(id, args) / getQuantityString(id, n, args).
//
// The tables are loaded once, on first use, and are immutable afterwards: the getters may be called from any
// thread. Images are decoded once with ImageIO and kept in a memory-bounded cache.

/// A string, plurals or array resource: its Android name (R.string.x == "x"; android.R.string.x == "android:x").
typealias AStringRes = String
/// A drawable or mipmap resource: its Android name (the file name without extension).
typealias ADrawableRes = String
/// A raw resource: its Android name.
typealias ARawRes = String

/// android.util.DisplayMetrics of the app window, in Android pixels (DESIGN 2.5).
struct ADisplayMetrics {
    /// UIScreen scale (2 or 3): 1 dp = density px.
    let density: Float
    let widthPixels: Int
    let heightPixels: Int
    /// density × fontScale; the font scale is 1 (Dynamic Type is not applied, DESIGN 2.5).
    let scaledDensity: Float
    /// DisplayMetrics.densityDpi (160 dpi per density unit: 320 or 480).
    var densityDpi: Int { Int((density * 160).rounded()) }
}

/// `v * resources.displayMetrics.density`.
func dp(_ v: Float) -> Float { v * AResources.density }

/// `v * resources.displayMetrics.density` for an Int (Kotlin converts the Int to Float first).
func dp(_ v: Int) -> Float { Float(v) * AResources.density }

// MARK: - Context / Resources string getters (Android names)

/// Resources.getString(id): the raw text, never formatted ("…0%" stays "…0%").
func getString(_ id: AStringRes) -> String {
    AResources.getString(id)
}

/// Resources.getString(id, formatArgs): `String.format(configuration.locales[0], raw, formatArgs)`.
func getString(_ id: AStringRes, _ args: Any?...) -> String {
    AResources.format(AResources.getString(id), args)
}

/// Resources.getQuantityString(id, quantity): the plural text for the quantity, not formatted.
func getQuantityString(_ id: AStringRes, _ quantity: Int) -> String {
    AResources.getQuantityString(id, quantity)
}

/// Resources.getQuantityString(id, quantity, formatArgs).
func getQuantityString(_ id: AStringRes, _ quantity: Int, _ args: Any?...) -> String {
    AResources.format(AResources.getQuantityString(id, quantity), args)
}

/// Resources.getStringArray(id).
func getStringArray(_ id: AStringRes) -> [String] {
    AResources.getStringArray(id)
}

/// Resources.getText(id). The app has no styled strings (the sync script stops on one), so the text is the
/// same as getString.
func getText(_ id: AStringRes) -> String {
    AResources.getText(id)
}

/// ContextCompat.getColor(context, R.color.x): R.color already holds the ARGB colour.
func ContextCompat_getColor(_ color: Int) -> Int {
    color
}

// MARK: - AResources

enum AResources {

    // MARK: Display (DESIGN 2.5)

    /// DisplayMetrics.density = UIScreen scale. Constant for the device; read once on the main thread.
    static var density: Float {
        let cached = densityCache.withLock { $0 }
        if cached != 0 {
            return cached
        }
        // No lock is held while waiting for the main thread.
        let scale = onMainThread { Float(UIScreen.main.scale) }
        densityCache.withLock { $0 = scale }
        return scale
    }

    /// Resources.getDisplayMetrics(): density and the app window size in px (the current orientation).
    /// Call it on the main thread (another thread waits for the main thread to read the window).
    static var displayMetrics: ADisplayMetrics {
        let size = onMainThread { windowSizeInPoints() }
        let density = self.density
        let scale = CGFloat(density)
        return ADisplayMetrics(density: density,
                               widthPixels: Int((size.width * scale).rounded()),
                               heightPixels: Int((size.height * scale).rounded()),
                               scaledDensity: density)
    }

    // MARK: Language (DESIGN 2.7)

    /// Resources' `configuration.locales[0]`: the device locale the resources act for (strings, plural rules,
    /// format locale). The app window's configuration, i.e. the first of Locale.preferredLanguages.
    static var configurationLocale: ALocale {
        if let locale = localeOverride {
            return locale
        }
        return AConfiguration.locales.locales.first ?? ALocale.getDefault()
    }

    /// The string table in use: "en" (values-en/) when the device language is English, else "he" (values/,
    /// the default, which Android also shows to every third language).
    static var language: String { tableLanguage(configurationLocale) }

    /// The app string table Android picks for a device locale: values-en only for the language "en". The locale is
    /// the first of Locale.preferredLanguages (never Bundle.main.preferredLocalizations, which would pick English for
    /// a [fr, en] device that Android shows in Hebrew).
    static func tableLanguage(_ locale: ALocale) -> String {
        locale.language.lowercased() == "en" ? "en" : "he"
    }

    /// Tests and QA only: the device locale every getter acts for (nil = the app window's configuration).
    nonisolated(unsafe) static var localeOverride: ALocale?

    /// Tests and QA only: `localeOverride` as a language tag ("he", "en", "fr-FR"); nil clears it.
    static var languageOverride: String? {
        get { localeOverride?.toLanguageTag() }
        set { localeOverride = newValue.map { ALocale.forLanguageTag($0) } }
    }

    // MARK: Strings

    /// One strings/<language>.json table.
    final class StringTable: Sendable {
        let language: String
        let strings: [String: String]
        let plurals: [String: [String: String]]
        let arrays: [String: [String]]
        /// The resources this table takes from values/ (English only).
        let untranslated: [String]

        init(_ json: [String: Any]) {
            language = json["language"] as? String ?? ""
            strings = json["strings"] as? [String: String] ?? [:]
            plurals = json["plurals"] as? [String: [String: String]] ?? [:]
            arrays = json["arrays"] as? [String: [String]] ?? [:]
            untranslated = json["untranslated"] as? [String] ?? []
        }
    }

    /// values/ (the default; Hebrew).
    static let hebrew = StringTable(loadJSON("strings/he.json"))
    /// values-en/ with the values/ fallback per resource.
    static let english = StringTable(loadJSON("strings/en.json"))
    /// android.R.string texts: name (without "android:") -> language ("" = the framework default) -> text.
    static let framework: [String: [String: String]] =
        loadJSON("strings/android.json")["strings"] as? [String: [String: String]] ?? [:]

    /// The prefix of the android.R.string ids ("android:cancel").
    static let frameworkPrefix = "android:"

    static func table(_ language: String) -> StringTable {
        language == "en" ? english : hebrew
    }

    /// getString for a device locale; a missing resource crashes like Android's Resources.NotFoundException.
    static func text(_ id: AStringRes, locale: ALocale) -> String {
        if id.hasPrefix(frameworkPrefix) {
            if let text = frameworkText(String(id.dropFirst(frameworkPrefix.count)), locale) {
                return text
            }
            notFound("String resource ID \(id)")
        }
        return text(id, language: tableLanguage(locale))
    }

    /// getString with the table of a language ("he" = values/, "en" = values-en/); android.R strings are taken
    /// for a device of that language.
    static func text(_ id: AStringRes, language: String) -> String {
        if id.hasPrefix(frameworkPrefix) {
            return text(id, locale: ALocale.forLanguageTag(language))
        }
        if let text = table(language).strings[id] ?? hebrew.strings[id] {
            return text
        }
        notFound("String resource ID \(id)")
    }

    /// The framework's resolution of android.R.string.<name> for a device locale: the language's own text
    /// (Serbian in Latin script has its own; Tagalog's serves Filipino, Android's langsAreEquivalent), else the
    /// framework default (values/, English). nil when the script did not export the string.
    static func frameworkText(_ name: String, _ locale: ALocale) -> String? {
        guard let texts = framework[name] else {
            return nil
        }
        var language = locale.language
        if language == "fil" {
            language = "tl"
        }
        if language == "sr", locale.script == "Latn", let latin = texts["sr-Latn"] {
            return latin
        }
        return texts[language] ?? texts[""]
    }

    /// Resources.getQuantityText for a device locale: the item named by the locale's plural rule for `quantity`
    /// (PluralRules.select), else "other"; the texts come from that locale's table.
    static func quantityText(_ id: AStringRes, _ quantity: Int, locale: ALocale) -> String {
        let language = tableLanguage(locale)
        guard let items = table(language).plurals[id] ?? hebrew.plurals[id] else {
            notFound("Plural resource ID \(id)")
        }
        let keyword = PluralRules.select(locale, quantity)
        if let text = items[keyword] {
            return text
        }
        if let text = items["other"] {
            return text
        }
        notFound("Plural resource ID \(id) quantity=\(quantity) item=\(keyword)")
    }

    /// Resources.getQuantityText for a device of `language` ("he" or "en"): that table and that language's rules.
    static func quantityText(_ id: AStringRes, _ quantity: Int, language: String) -> String {
        quantityText(id, quantity, locale: ALocale.forLanguageTag(language))
    }

    /// Resources.getStringArray for a device locale.
    static func stringArray(_ id: AStringRes, locale: ALocale) -> [String] {
        stringArray(id, language: tableLanguage(locale))
    }

    static func stringArray(_ id: AStringRes, language: String) -> [String] {
        if let array = table(language).arrays[id] ?? hebrew.arrays[id] {
            return array
        }
        notFound("String array resource ID \(id)")
    }

    // The getters under AResources, for `resources.getString(...)` call sites (the configuration's locale).
    static func getString(_ id: AStringRes) -> String {
        text(id, locale: configurationLocale)
    }
    static func getString(_ id: AStringRes, _ args: Any?...) -> String {
        format(getString(id), args)
    }
    static func getQuantityString(_ id: AStringRes, _ quantity: Int) -> String {
        quantityText(id, quantity, locale: configurationLocale)
    }
    static func getQuantityString(_ id: AStringRes, _ quantity: Int, _ args: Any?...) -> String {
        format(getQuantityString(id, quantity), args)
    }
    static func getStringArray(_ id: AStringRes) -> [String] {
        stringArray(id, locale: configurationLocale)
    }
    static func getText(_ id: AStringRes) -> String {
        getString(id)
    }

    /// `String.format(configuration.locales[0], raw, args)` (java.util.Formatter, AFormat).
    static func format(_ raw: String, _ args: [Any?]) -> String {
        AFormat.format(configurationLocale, raw, args)
    }

    // MARK: Identifiers (Resources.getIdentifier)

    static let packageName = "com.appsbybros.minik.swish"

    /// Resources.getIdentifier(name, defType, packageName): the resource id (its name) or nil where Android
    /// returns 0. `name` may be "type/entry" or "package:type/entry" like on Android.
    static func getIdentifier(_ name: String, _ defType: String) -> String? {
        var entry = Substring(name)
        var package = ""
        var type = defType
        if let colon = entry.firstIndex(of: ":") {
            package = String(entry[..<colon])
            entry = entry[entry.index(after: colon)...]
        }
        if let slash = entry.firstIndex(of: "/") {
            type = String(entry[..<slash])
            entry = entry[entry.index(after: slash)...]
        }
        let resource = String(entry)
        if resource.isEmpty {
            return nil
        }
        if package == "android" {
            return type == "string" && framework[resource] != nil ? frameworkPrefix + resource : nil
        }
        if !package.isEmpty && package != packageName {
            return nil
        }
        let exists: Bool
        switch type {
        case "drawable": exists = drawableExists(resource)
        case "string": exists = hebrew.strings[resource] != nil || english.strings[resource] != nil
        case "plurals": exists = hebrew.plurals[resource] != nil || english.plurals[resource] != nil
        case "array": exists = hebrew.arrays[resource] != nil || english.arrays[resource] != nil
        case "raw": exists = AResourceIndex.rawFiles[resource] != nil
        case "mipmap": exists = AResourceIndex.mipmap.contains(resource)
        case "color": exists = AResourceIndex.color.contains(resource)
        case "dimen": exists = AResourceIndex.dimen.contains(resource)
        case "layout": exists = AResourceIndex.layout.contains(resource)
        case "id": exists = AResourceIndex.id.contains(resource)
        case "style": exists = AResourceIndex.style.contains(resource)
        default: exists = false
        }
        return exists ? resource : nil
    }

    // MARK: Drawables

    /// One bitmap drawable of Res/drawable-sizes.json.
    struct DrawableFile {
        /// Below Res/, e.g. "drawable-nodpi/zephyr_steal_side.webp".
        let file: String
        let width: Int
        let height: Int
    }

    static let drawables: [String: DrawableFile] = {
        var table: [String: DrawableFile] = [:]
        for (name, value) in loadJSON("drawable-sizes.json") {
            guard let entry = value as? [String: Any], let file = entry["file"] as? String,
                  let width = entry["width"] as? Int, let height = entry["height"] as? Int else {
                preconditionFailure("AResources: bad drawable-sizes.json entry \(name)")
            }
            table[name] = DrawableFile(file: file, width: width, height: height)
        }
        return table
    }()

    /// R.drawable has the name: a bitmap or an XML drawable (XML drawables are ported in Swift).
    static func drawableExists(_ name: ADrawableRes) -> Bool {
        drawables[name] != nil || AResourceIndex.xmlDrawables.contains(name)
    }

    /// The image's pixel size: Android's intrinsic size of a drawable-nodpi image, and what BitmapFactory
    /// decodes with inScaled=false. (-1, -1) for an XML drawable or an unknown name (no intrinsic size).
    static func drawablePixelSize(_ name: ADrawableRes) -> (width: Int, height: Int) {
        guard let drawable = drawables[name] else { return (-1, -1) }
        return (drawable.width, drawable.height)
    }

    /// Drawable.getIntrinsicWidth/Height of ContextCompat.getDrawable(R.drawable.x) for a bitmap: drawable-nodpi
    /// images keep their pixel size; drawable/ images count as mdpi and are scaled by densityDpi / 160 at
    /// decode time (BitmapFactory: `(int) (size * scale + 0.5f)`). (-1, -1) for XML drawables and unknown names.
    static func drawableIntrinsicSize(_ name: ADrawableRes) -> (width: Int, height: Int) {
        guard let drawable = drawables[name] else { return (-1, -1) }
        if !drawable.file.hasPrefix("drawable/") {
            return (drawable.width, drawable.height)
        }
        let scale = Float(Int((density * 160).rounded())) / 160
        return (Int(Float(drawable.width) * scale + 0.5), Int(Float(drawable.height) * scale + 0.5))
    }

    /// The image file in the app bundle; nil for XML drawables and unknown names.
    static func drawableURL(_ name: ADrawableRes) -> URL? {
        drawables[name].map { resURL.appendingPathComponent($0.file) }
    }

    /// The decoded image (ImageIO; WebP is native), scale 1 so `size` is the pixel size. Decoded once and kept
    /// in a memory-bounded cache (the whole set would be ~420 MB decoded; like Android's drawable cache, an image
    /// nobody holds may be dropped and decoded again later). nil for XML drawables.
    static func image(_ name: ADrawableRes) -> UIImage? {
        let key = name as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let url = drawableURL(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else {
            return nil
        }
        let image = UIImage(cgImage: decoded, scale: 1, orientation: .up)
        imageCache.setObject(image, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        return image
    }

    static func cgImage(_ name: ADrawableRes) -> CGImage? {
        image(name)?.cgImage
    }

    // MARK: Raw and assets

    static func rawURL(_ name: ARawRes) -> URL? {
        AResourceIndex.rawFiles[name].map { resURL.appendingPathComponent($0) }
    }

    /// java.io.FileNotFoundException of AssetManager.open.
    struct FileNotFoundException: Error, CustomStringConvertible {
        let path: String
        var description: String { "java.io.FileNotFoundException: \(path)" }
    }

    /// AssetManager.open(path), e.g. "question_banks/en/english.xml".
    static func openAsset(_ path: String) throws -> Data {
        guard assetExists(path), let data = try? Data(contentsOf: assetURL(path), options: .mappedIfSafe) else {
            throw FileNotFoundException(path: path)
        }
        return data
    }

    /// An asset file exists at `path` (a folder is not an asset).
    static func assetExists(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: assetURL(path).path, isDirectory: &directory) && !directory.boolValue
    }

    static func assetURL(_ path: String) -> URL {
        resURL.appendingPathComponent("assets", isDirectory: true).appendingPathComponent(path)
    }

    // MARK: Bundle

    /// Res/ in the bundle that holds this module's code (the app; also inside hosted unit tests).
    static let resURL: URL = {
        let bundle = Bundle(for: AResourcesBundleToken.self)
        return (bundle.resourceURL ?? bundle.bundleURL).appendingPathComponent("Res", isDirectory: true)
    }()

    // MARK: Private

    /// UIScreen scale, 0 until first read.
    private static let densityCache = OSAllocatedUnfairLock<Float>(initialState: 0)

    // NSCache is thread-safe.
    nonisolated(unsafe) private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.name = "AResources.images"
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    private static func loadJSON(_ path: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: resURL.appendingPathComponent(path)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            preconditionFailure("AResources: Res/\(path) is missing from the app bundle (Scripts/tripleshot-sync-resources.py "
                                + "writes it; TripleShot/Res must be a folder reference named Res)")
        }
        return json
    }

    private static func notFound(_ what: String) -> Never {
        preconditionFailure("android.content.res.Resources$NotFoundException: \(what)")
    }

    /// Runs UIKit reads on the main thread (synchronously from another thread).
    private static func onMainThread<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }

    @MainActor private static func windowSizeInPoints() -> CGSize {
        var screen: UIScreen?
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            screen = windowScene.screen
            let windows = windowScene.windows
            if let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first, window.bounds.width > 0 {
                return window.bounds.size
            }
        }
        return (screen ?? UIScreen.main).bounds.size
    }
}

/// Finds the bundle of this module's code (Bundle(for:)).
private final class AResourcesBundleToken {}
