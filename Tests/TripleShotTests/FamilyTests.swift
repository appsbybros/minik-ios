import XCTest
@testable import MinikTripleShot

/// Parity tests of the family look (spec 22 §7.1, 18-home §4.4, 19-dialogs §4.5). Expected values come from a JVM oracle
/// running the Java maths of FamilySkyDrawable.java (family 2f75e98) — Color.colorToHSV as Skia's float SkRGBToHSV,
/// Math.round, float geometry — the TripleShotButton ink rule and FamilyReadingPanel.contentWidth
/// (scratch work/t-family/oracle/Golden.java), and from the colour tables of spec 22 §7.1.5 / 18-home §4.4.5–4.4.6.
final class FamilyTests: XCTestCase {
    private func c(_ v: UInt32) -> Int { return argbInt(v) }

    // MARK: palette (HSV saturation 0.12 ... 0.48 by hue band; source alpha kept)

    func testPaletteMapsPaleFillsByHue() {
        let cases: [(UInt32, UInt32)] = [
            (0xffb8d9ff, 0xffa6dcff),   // FamilyMenu.LEARN, exit "Save": hue 212.1, s 0.278
            (0xffb9f4dc, 0xffb1eddb),   // FamilyMenu.PLAY: hue 155.6
            (0xffe8dcff, 0xffa6dcff),   // FamilyMenu.SAVED: hue 260.57 < 265 -> blue, not purple
            (0xffe8e0ff, 0xffa6dcff),   // exit "Cancel": s 0.1216, hue 255.5 -> blue
            (0xffb9ebf4, 0xffa6dcff),   // journey / Settings buttons
            (0xff89deff, 0xffa6dcff),   // League default button
            (0xffc6a0ff, 0xffa6dcff),   // League purple: hue exactly 264.0
            (0xff80e4bd, 0xffb1eddb),   // League green
            (0xffa6dcff, 0xffa6dcff),   // already the Maze blue
            (0xffd9edff, 0xffa6dcff),   // League own standings row (flattened later, raw colour kept there)
            (0xffdceeff, 0xffa6dcff),   // family card link fill
            (0xffc8f1e6, 0xffb1eddb),   // family card "Keep playing" fill
            (0xffd0a0ff, 0xffd8bfff),   // hue 270.3: the purple band
            (0xe8fff7dc, 0xe8ffe59d),   // hue 46.3: the yellow band, alpha kept
        ]
        for (source, painted) in cases {
            XCTAssertEqual(FamilySkyDrawable.palette(color: c(source)), c(painted), String(format: "palette(#%08X)", source))
        }
        XCTAssertEqual(FamilySkyDrawable.palette(c(0xffe8dcff)), c(0xffa6dcff))   // the unlabelled form
    }

    func testPaletteKeepsGreyStrongAndOtherHues() {
        let kept: [UInt32] = [
            0xffffe082,   // FamilyMenu.ADVANCED: s 0.4902 > 0.48
            0xffe91e63,   // exit "Don't save" (strong)
            0xfff6f8ff,   // exit panel (s 0.035)
            0xffffffff, 0xfaffffff, 0xff000000, 0x00000000, 0x28ffffff,
            0xffffd4e6,   // dialog negative: hue 334.9 is outside every band
            0xffff97bd,   // League pink: hue 338.1
            0xffffc0cb,   // hue 349.5
            0xff087e70, 0xff087e69, 0xff008b7a,   // Material colorPrimary and the bot setup / Live greens
            0xff0b8b78, 0xffb9534d,   // Progress badges
            0xff76d8ff, 0xffffb779, 0xfff5d66f,   // League palette entries above 0.48
            0xff176ac0,   // bot setup selected size
            0xff8080ff, 0xffc080ff,   // s 0.498: just above the band
            0xffe5f1ff, 0xffe8f1ef, 0xffd9e5f6, 0xffe0e9fa,   // s < 0.12
            0xfffffdf8, 0xfff8f5fc, 0xfff5fbfa,   // bot setup card fills
        ]
        for color in kept {
            XCTAssertEqual(FamilySkyDrawable.palette(color: c(color)), c(color), String(format: "palette(#%08X)", color))
        }
    }

    func testPaletteKeepsTheSourceAlpha() {
        XCTAssertEqual(FamilySkyDrawable.palette(color: c(0x80b8d9ff)), c(0x80a6dcff))
        XCTAssertEqual(FamilySkyDrawable.palette(color: c(0x00b8d9ff)), c(0x00a6dcff))
        XCTAssertEqual(FamilySkyDrawable.palette(color: c(0xdab9f4dc)), c(0xdab1eddb))
    }

    // MARK: blend (Java float maths: (1 - t) in float, Math.round half up, always opaque)

    /// The face (upper, lower), lip and rim colours of the pale call-site faces (factors 0.75 / 0.32 / 0.28 / 0.22).
    func testPaleFaceColoursOfTheCallSites() {
        struct Row { let base: UInt32; let upper: UInt32; let lower: UInt32; let edge: UInt32; let rim: UInt32 }
        let rows = [
            Row(base: 0xffa6dcff, upper: 0xffe9f6ff, lower: 0xffc2e7ff, edge: 0xff80b3d9, rim: 0xffbae4ff),   // LEARN / SAVED / Save / Cancel
            Row(base: 0xffb1eddb, upper: 0xffecfbf6, lower: 0xffcaf3e7, edge: 0xff88bfbf, rim: 0xffc2f1e3),   // PLAY
            Row(base: 0xffffe082, upper: 0xfffff7e0, lower: 0xffffeaaa, edge: 0xffc1b57f, rim: 0xffffe79e),   // ADVANCED
            Row(base: 0xffffd4e6, upper: 0xfffff4f9, lower: 0xffffe2ee, edge: 0xffc1adc7, rim: 0xffffddec),   // dialog negative
            Row(base: 0xfff6f8ff, upper: 0xfffdfdff, lower: 0xfff9faff, edge: 0xffbac7d9, rim: 0xfff8faff),   // exit panel
        ]
        for row in rows {
            let base = c(row.base)
            XCTAssertEqual(FamilySkyDrawable.blend(base, AColor.WHITE, 0.75), c(row.upper), String(format: "upper #%08X", row.base))
            XCTAssertEqual(FamilySkyDrawable.blend(base, AColor.WHITE, 0.32), c(row.lower), String(format: "lower #%08X", row.base))
            XCTAssertEqual(FamilySkyDrawable.blend(base, c(0xff204878), 0.28), c(row.edge), String(format: "edge #%08X", row.base))
            XCTAssertEqual(FamilySkyDrawable.blend(base, AColor.WHITE, 0.22), c(row.rim), String(format: "rim #%08X", row.base))
        }
    }

    /// Dark faces (luminance < 130) use 0.08 / 0.015; several channel sums land exactly on .5 (Math.round rounds up).
    func testDarkFaceColours() {
        let pink = c(0xffe91e63)
        XCTAssertEqual(FamilySkyDrawable.blend(pink, AColor.WHITE, 0.08), c(0xffeb306f))
        XCTAssertEqual(FamilySkyDrawable.blend(pink, AColor.WHITE, 0.015), c(0xffe92165))
        XCTAssertEqual(FamilySkyDrawable.blend(pink, c(0xff204878), 0.28), c(0xffb12a69))
        XCTAssertEqual(FamilySkyDrawable.blend(pink, AColor.WHITE, 0.22), c(0xffee5085))
        let teal = c(0xff087e70)
        XCTAssertEqual(FamilySkyDrawable.blend(teal, AColor.WHITE, 0.08), c(0xff1c887b))
        XCTAssertEqual(FamilySkyDrawable.blend(teal, AColor.WHITE, 0.015), c(0xff0c8072))
        XCTAssertEqual(FamilySkyDrawable.blend(teal, c(0xff204878), 0.28), c(0xff0f6f72))
        XCTAssertEqual(FamilySkyDrawable.blend(teal, AColor.WHITE, 0.22), c(0xff3e9a8f))
        let selected = c(0xff176ac0)
        XCTAssertEqual(FamilySkyDrawable.blend(selected, AColor.WHITE, 0.08), c(0xff2a76c5))
        XCTAssertEqual(FamilySkyDrawable.blend(selected, AColor.WHITE, 0.015), c(0xff1a6cc1))
        XCTAssertEqual(FamilySkyDrawable.blend(selected, c(0xff204878), 0.28), c(0xff1a60ac))
        let badge = c(0xffb9534d)
        XCTAssertEqual(FamilySkyDrawable.blend(badge, AColor.WHITE, 0.08), c(0xffbf615b))
        XCTAssertEqual(FamilySkyDrawable.blend(badge, AColor.WHITE, 0.015), c(0xffba5650))
        // Neither pale nor dark (the gold room-panel start button): 0.22 / 0.02.
        let gold = c(0xffffc83d)
        XCTAssertEqual(FamilySkyDrawable.blend(gold, AColor.WHITE, 0.22), c(0xffffd468))
        XCTAssertEqual(FamilySkyDrawable.blend(gold, AColor.WHITE, 0.02), c(0xffffc941))
        XCTAssertEqual(FamilySkyDrawable.blend(gold, c(0xff204878), 0.28), c(0xffc1a44e))
    }

    /// Panels and near-white faces: the two tinted diagonal stops (18-home §4.4.5 section panels).
    func testDiagonalFaceStops() {
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffdff5ff), c(0xfff6f8ff), 0.1), c(0xffe1f5ff))   // exit panel
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffffdeeb), c(0xfff6f8ff), 0.08), c(0xfffee0ed))
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffdff5ff), AColor.WHITE, 0.1), c(0xffe2f6ff))    // dialog panel, white rows
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffffdeeb), AColor.WHITE, 0.08), c(0xffffe1ed))
        XCTAssertEqual(FamilySkyDrawable.blend(AColor.WHITE, c(0xff204878), 0.28), c(0xffc1ccd9))
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffdff5ff), c(0xffa6dcff), 0.1), c(0xffd9f3ff))   // LEARN / SAVED section panel
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffffdeeb), c(0xffa6dcff), 0.08), c(0xfff8deed))
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffdff5ff), c(0xffb1eddb), 0.1), c(0xffdaf4fb))   // PLAY section panel
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffffdeeb), c(0xffb1eddb), 0.08), c(0xfff9dfea))
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffdff5ff), c(0xffffe082), 0.1), c(0xffe2f3f3))   // ADVANCED section panel
        XCTAssertEqual(FamilySkyDrawable.blend(c(0xffffdeeb), c(0xffffe082), 0.08), c(0xffffdee3))
        XCTAssertEqual(FamilySkyDrawable.blend(c(0x40ffffff), AColor.BLACK, 0), AColor.WHITE)        // always opaque
    }

    // MARK: geometry (spec 22 §7.1.4; px)

    private func sky(_ width: Int, _ height: Int, radius: Float?, panel: Bool = false, pressed: Bool = false,
                     color: UInt32 = 0xffb8d9ff) -> FamilySkyDrawable {
        let d = FamilySkyDrawable(panel: panel)
        d.setColor(c(color)); if let r = radius { d.setCornerRadius(r) }; d.setBounds(0, 0, width, height)
        var states = [android.R.attr.state_enabled]
        if pressed { states.append(android.R.attr.state_pressed) }
        d.setState(states)
        return d
    }

    func testHomeSectionButtonFace() {
        let d = sky(300, 56, radius: 15)
        let face = ARectF(); d.copyFaceBounds(out: face)
        XCTAssertEqual(face.left, 1.2, accuracy: 1e-4); XCTAssertEqual(face.top, 1.2, accuracy: 1e-4)
        XCTAssertEqual(face.right, 298.8, accuracy: 1e-4); XCTAssertEqual(face.bottom, 50.6, accuracy: 1e-4)
        let text = ARectF(); d.copyTextFaceBounds(out: text)
        XCTAssertEqual(text.top, 10.95, accuracy: 1e-4)          // + min(0.20 * 49.4, 0.65 * 15)
        XCTAssertEqual(text.centerY(), 30.775, accuracy: 1e-4)   // 2.775 px below the bounds centre
    }

    func testLeagueExitButtonFaceAtRestAndPressed() {
        let rest = ARectF(); sky(320, 64, radius: 16).copyTextFaceBounds(out: rest)
        XCTAssertEqual(rest.top, 11.68, accuracy: 1e-4); XCTAssertEqual(rest.bottom, 58.24, accuracy: 1e-4)
        XCTAssertEqual(rest.centerY(), 34.96, accuracy: 1e-4)
        let down = ARectF(); sky(320, 64, radius: 16, pressed: true).copyTextFaceBounds(down)
        XCTAssertEqual(down.top, 14.592, accuracy: 1e-4); XCTAssertEqual(down.bottom, 61.376, accuracy: 1e-4)
        XCTAssertEqual(down.centerY() - rest.centerY(), 3.024, accuracy: 1e-4)
    }

    /// The default radius is 18 px (a Material dialog button of the gate): rim 1.248, depth 3.6.
    func testDefaultRadiusAndPressedDialogButton() {
        let rest = ARectF(); sky(300, 48, radius: nil).copyTextFaceBounds(out: rest)
        XCTAssertEqual(rest.top, 9.6288, accuracy: 1e-4); XCTAssertEqual(rest.bottom, 43.152, accuracy: 1e-4)
        XCTAssertEqual(rest.centerY(), 26.3904, accuracy: 1e-4)
        let down = ARectF(); sky(300, 48, radius: nil, pressed: true).copyTextFaceBounds(out: down)
        XCTAssertEqual(down.centerY(), 28.8384, accuracy: 1e-4)
    }

    func testPanelsNeverSinkAndHaveNoGlossBand() {
        let rest = ARectF(); sky(400, 200, radius: 24, panel: true).copyTextFaceBounds(out: rest)
        let down = ARectF(); sky(400, 200, radius: 24, panel: true, pressed: true).copyTextFaceBounds(out: down)
        // rim = max(1, min(5.2, 1.92)) = 1.92; depth = min(15, max(2, 6.72)) = 6.72
        XCTAssertEqual(rest.top, 1.92, accuracy: 1e-4); XCTAssertEqual(rest.bottom, 191.36, accuracy: 1e-4)
        XCTAssertEqual(down.top, rest.top, accuracy: 1e-6); XCTAssertEqual(down.bottom, rest.bottom, accuracy: 1e-6)
    }

    func testSmallAndSquareCornerSurfacesUseTheMinimumRimAndDepth() {
        // 20 x 20 px, radius 4: depth = min(1.5, max(2, 1.12)) = 1.5; rim = max(1, min(0.52, 0.32)) = 1
        let small = ARectF(); sky(20, 20, radius: 4).copyFaceBounds(out: small)
        XCTAssertEqual(small.top, 1, accuracy: 1e-5); XCTAssertEqual(small.bottom, 17.5, accuracy: 1e-5)
        // radius 0: depth = max(2, 0) = 2, rim 1, and no gloss band above the lettering (min(..., 0) = 0)
        let square = ARectF(); sky(300, 56, radius: 0).copyTextFaceBounds(out: square)
        XCTAssertEqual(square.top, 1, accuracy: 1e-5); XCTAssertEqual(square.bottom, 53, accuracy: 1e-5)
    }

    /// Java `getOutline`: `round(box inset rim)`, the corner radius and `alpha(base) / 255`.
    func testOutlineFollowsTheLipRect() {
        let outline = AOutline(); sky(300, 56, radius: 15).getOutline(outline)
        XCTAssertEqual(outline.rect?.left, 1); XCTAssertEqual(outline.rect?.top, 1)
        XCTAssertEqual(outline.rect?.right, 299); XCTAssertEqual(outline.rect?.bottom, 55)
        XCTAssertEqual(outline.radius, 15); XCTAssertEqual(outline.alpha, 1, accuracy: 1e-6)
        let translucent = AOutline(); sky(300, 56, radius: 15, color: 0x80b8d9ff).getOutline(translucent)
        XCTAssertEqual(translucent.alpha, Float(128) / 255, accuracy: 1e-6)
    }

    /// Kotlin `cornerRadius = x` / `alpha = x` on a GradientDrawable-typed reference and Java `setColor(null)` reach the
    /// overrides.
    func testOverridesAreReachedThroughTheGradientDrawableAPI() {
        let g: AGradientDrawable = FamilySkyDrawable()
        g.cornerRadius = 15; g.setColor(c(0xffb8d9ff)); g.setBounds(0, 0, 300, 56); g.setState([android.R.attr.state_enabled])
        let text = ARectF(); (g as! FamilySkyDrawable).copyTextFaceBounds(text)
        XCTAssertEqual(text.top, 10.95, accuracy: 1e-4)
        XCTAssertEqual(g.cornerRadius, 15)
        g.setAlpha(128); XCTAssertEqual(g.alpha, 128)
        let d = FamilySkyDrawable(); d.setColor(nil as AColorStateList?)
        XCTAssertEqual(d.sourceColors().defaultColor, AColor.TRANSPARENT)   // GradientDrawable.setColor(null) -> setColor(TRANSPARENT)
        XCTAssertTrue(d.isStateful); XCTAssertFalse(d.isPanel); XCTAssertTrue(FamilySkyDrawable(true).isPanel)
        XCTAssertTrue(FamilySkyDrawable(panel: true).isPanel)
    }

    func testFamilyMenuColours() {
        XCTAssertEqual(FamilyMenu.LEARN, c(0xffb8d9ff)); XCTAssertEqual(FamilyMenu.PLAY, c(0xffb9f4dc))
        XCTAssertEqual(FamilyMenu.SAVED, c(0xffe8dcff)); XCTAssertEqual(FamilyMenu.ADVANCED, c(0xffffe082))
        XCTAssertEqual(FamilyMenu.LINK, c(0xff2869bd)); XCTAssertEqual(FamilyMenu.INK, c(0xff282d4e))
    }

    // MARK: TripleShotButton lettering ink: (299R + 587G + 114B) / 1000 < 130 && enabled -> white, else #23384D

    func testTripleShotButtonInkRule() {
        let ink = c(0xff23384d)
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff087e70), isEnabled: true), AColor.WHITE)    // luminance 89
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff087e70), isEnabled: false), ink)            // disabled: never white
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff176ac0), isEnabled: true), AColor.WHITE)    // 90: selected bot setup sizes
        XCTAssertEqual(TripleShotButton.ink(color: c(0xffe91e63), isEnabled: true), AColor.WHITE)    // 98
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff008b7a), isEnabled: true), AColor.WHITE)    // 95: Live setup
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff7657d6), isEnabled: true), AColor.WHITE)    // 110: game result Leaderboard
        XCTAssertEqual(TripleShotButton.ink(color: c(0xffa6dcff), isEnabled: true), ink)             // 207
        XCTAssertEqual(TripleShotButton.ink(color: c(0xffffe082), isEnabled: true), ink)             // 222
        XCTAssertEqual(TripleShotButton.ink(color: c(0xffffc83d), isEnabled: true), ink)             // 200
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff828282), isEnabled: true), ink)             // exactly 130: not dark
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff818181), isEnabled: true), AColor.WHITE)    // 129
        XCTAssertEqual(TripleShotButton.ink(color: c(0xff7f7f7f), isEnabled: true), AColor.WHITE)    // 127
        // The rule reads the palette-mapped face: a pale journey button paints #A6DCFF and keeps the dark ink.
        XCTAssertEqual(TripleShotButton.ink(color: FamilySkyDrawable.palette(color: c(0xffb9ebf4)), isEnabled: true), ink)
    }

    // MARK: FamilyReadingPanel.contentWidth

    func testReadingWidthPortraitAndSquareKeepTheAvailableWidth() {
        XCTAssertEqual(FamilyReadingPanel.contentWidth(widthPixels: 1179, heightPixels: 2556, density: 3, available: 1100), 1100)
        XCTAssertEqual(FamilyReadingPanel.contentWidth(widthPixels: 2048, heightPixels: 2048, density: 2, available: 1900), 1900)
    }

    func testReadingWidthLandscape() {
        // min(available, min(round(520 d), max(round(300 d), round(0.52 available))))
        let cases: [(Int, Int, Float, Int, Int)] = [
            (2556, 1179, 3, 2400, 1248),   // 0.52 * 2400
            (2556, 1179, 3, 2403, 1250),   // round(1249.56)
            (2556, 1179, 3, 1153, 900),    // at least 300 dp
            (2732, 2048, 2, 2732, 1040),   // capped at 520 dp
            (2732, 2048, 2, 2201, 1040),   // round(1144.52) > 1040
            (1280, 800, 2, 800, 600),      // at least 300 dp
            (1280, 800, 2, 500, 500),      // never wider than available
            (2532, 1170, 3, 1500, 900),
            (2796, 1290, 3, 2662, 1384),
            (2388, 1668, 2, 2200, 1040),
            (2388, 1668, 2, 1900, 988),
            (1366, 1024, 1, 1366, 520),
            (1366, 1024, 1, 900, 468),
        ]
        for (w, h, d, available, expected) in cases {
            XCTAssertEqual(FamilyReadingPanel.contentWidth(widthPixels: w, heightPixels: h, density: d, available: available), expected,
                           "\(w)x\(h) @\(d) available \(available)")
        }
    }

    /// The bot setup dialog asks `contentWidth(ctx, (widthPixels * 0.94f).toInt())` once, when it is built.
    func testBotSetupDialogWidth() {
        XCTAssertEqual(FamilyReadingPanel.contentWidth(widthPixels: 1179, heightPixels: 2556, density: 3, available: (Float(1179) * 0.94).toInt()), 1108)
        XCTAssertEqual(FamilyReadingPanel.contentWidth(widthPixels: 2556, heightPixels: 1179, density: 3, available: (Float(2556) * 0.94).toInt()), 1249)
    }

    // MARK: Family copy language (FamilyMessages.text / language)

    func testFamilyTextFollowsTheDeviceLanguage() {
        XCTAssertEqual(FamilyBridge.language(tag: "iw-IL"), "he")
        XCTAssertEqual(FamilyBridge.language(tag: "he-IL"), "he-IL")
        XCTAssertEqual(FamilyBridge.language(tag: "en-US"), "en-US")
        let cases: [(String, String)] = [
            ("he-IL", "עוד למטה"), (FamilyBridge.language(tag: "iw"), "עוד למטה"), ("es-ES", "Más abajo"), ("fr", "Plus bas"),
            ("ar-EG", "المزيد بالأسفل"), ("pt-BR", "Mais abaixo"), ("uk-UA", "Ще нижче"), ("en-US", "More below"),
            ("zh-Hans-CN", "More below"), ("", "More below"),
        ]
        for (tag, expected) in cases {
            XCTAssertEqual(FamilyBridge.text(language: tag, "More below", "עוד למטה"), expected, tag)
        }
        XCTAssertEqual(FamilyBridge.text(language: "de-DE", "More options below. Tap to scroll", "עוד אפשרויות למטה. הקישו לגלילה"),
                       "Weitere Optionen unten. Zum Scrollen tippen")
        XCTAssertEqual(FamilyBridge.text(language: "es", "Not in the table", "לא בטבלה"), "Not in the table")
    }

    // MARK: java.util.WeakHashMap emulation (identity keys, weak keys)

    func testWeakHashMapUsesIdentityAndReleasesItsKeys() {
        final class Key {}
        let map = FamilyWeakHashMap<Key, Int>()
        var key: Key? = Key()
        let other = Key()
        map.put(key!, 1)
        XCTAssertEqual(map.get(key!), 1); XCTAssertTrue(map.containsKey(key!)); XCTAssertNil(map.get(other))
        map.put(key!, 2); XCTAssertEqual(map.get(key!), 2); XCTAssertEqual(map.size, 1)
        XCTAssertEqual(map.remove(key!), 2); XCTAssertFalse(map.containsKey(key!))
        map.put(key!, 3); map.put(other, 4); XCTAssertEqual(map.size, 2)
        key = nil
        XCTAssertEqual(map.size, 1); XCTAssertEqual(map.get(other), 4)
    }
}
