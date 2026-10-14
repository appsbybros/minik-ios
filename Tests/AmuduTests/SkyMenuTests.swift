import XCTest
@testable import MinikAmudu

/// The 2026-10-13 shared menu surfaces (Android `FamilySkyDrawable.palette`/`blend` and `FamilyReadingPanel`), as the
/// Spud screens use them.
final class SkyMenuTests: XCTestCase {
    func testPaletteKeepsStrongAndNearWhiteColorsAndMapsPaleFills() {
        // Mid-pale fills take the shared sky colours by hue.
        XCTAssertEqual(SkyPalette.palette(0xffc5ecff), 0xffa6dcff)
        XCTAssertEqual(SkyPalette.palette(0xffb8d9ff), 0xffa6dcff)
        XCTAssertEqual(SkyPalette.palette(0xffb9f4dc), 0xffb1eddb)
        XCTAssertEqual(SkyPalette.palette(0xffb8f3dc), 0xffb1eddb)
        // Strong, near-white and grey colours keep their roles; alpha is kept.
        XCTAssertEqual(SkyPalette.palette(0xff153c54), 0xff153c54)
        XCTAssertEqual(SkyPalette.palette(0xffffe082), 0xffffe082)
        XCTAssertEqual(SkyPalette.palette(0xffe3f4ff), 0xffe3f4ff)
        XCTAssertEqual(SkyPalette.palette(0xffffffff), 0xffffffff)
        XCTAssertEqual(SkyPalette.palette(0xb53c7b75), 0xb53c7b75)
        XCTAssertEqual(SkyPalette.palette(0x80c5ecff), 0x80a6dcff)
    }

    func testBlendIsOpaqueAndRounded() {
        XCTAssertEqual(SkyPalette.blend(0xff000000, 0xffffffff, 0.5), 0xff808080)
        XCTAssertEqual(SkyPalette.blend(0x00102030, 0xff102030, 0.3), 0xff102030)
        XCTAssertTrue(SkyPalette.isPanelFill(0xffffffff))
        XCTAssertFalse(SkyPalette.isPanelFill(0xffb8f3dc))
    }

    func testReadingPanelIsFullWidthInPortraitAndCentredColumnInLandscape() {
        XCTAssertEqual(ReadingPanel.width(available: 390, window: CGSize(width: 390, height: 844)), 390)
        XCTAssertEqual(ReadingPanel.width(available: 800, window: CGSize(width: 844, height: 390)), 416)
        XCTAssertEqual(ReadingPanel.width(available: 1300, window: CGSize(width: 1366, height: 1024)), 520)
        XCTAssertEqual(ReadingPanel.width(available: 500, window: CGSize(width: 568, height: 320)), 300)
        XCTAssertEqual(ReadingPanel.width(available: 280, window: CGSize(width: 300, height: 200)), 280)
    }
}
