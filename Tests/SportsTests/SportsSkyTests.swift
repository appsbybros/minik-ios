import XCTest
@testable import MinikSquash

/// The shared Android presentation of 13 October 2026 as drawn by the sports pages: FamilySkyDrawable's
/// palette (pale, mid-saturation fills become Maze's equivalents) and FamilyReadingPanel's column.
final class SportsSkyTests: XCTestCase {
    func testPaletteMapsPaleFillsByHue() {
        // FamilyMenu section colours: Start & learn, Play and Saved games (hue 261, so blue); Advanced
        // is saturated enough to keep its yellow.
        XCTAssertEqual(SportsSky.palette(0xffb8d9ff), 0xffa6dcff)
        XCTAssertEqual(SportsSky.palette(0xffb9f4dc), 0xffb1eddb)
        XCTAssertEqual(SportsSky.palette(0xffe8dcff), 0xffa6dcff)
        XCTAssertEqual(SportsSky.palette(0xffffe082), 0xffffe082)
        // Page buttons: the default green, Start challenge's yellow and the Next blue.
        XCTAssertEqual(SportsSky.palette(0xffc6ecdd), 0xffb1eddb)
        XCTAssertEqual(SportsSky.palette(0xffffdf85), 0xffffe59d)
        XCTAssertEqual(SportsSky.palette(0xffb7e6fb), 0xffa6dcff)
    }

    func testPaletteKeepsGrayAndStrongColours() {
        XCTAssertEqual(SportsSky.palette(0xffdfedf6), 0xffdfedf6)
        XCTAssertEqual(SportsSky.palette(0xfff8e0ec), 0xfff8e0ec)
        XCTAssertEqual(SportsSky.palette(0xfff6f8ff), 0xfff6f8ff)
        XCTAssertEqual(SportsSky.palette(0xffe91e63), 0xffe91e63)
        XCTAssertEqual(SportsSky.palette(0x00000000), 0x00000000)
    }

    func testBlend() {
        XCTAssertEqual(SportsSky.blend(0xffa6dcff, 0xffffffff, 0.75), 0xffe9f6ff)
        XCTAssertEqual(SportsSky.blend(0xffa6dcff, 0xff204878, 0.28), 0xff80b3d9)
    }

    func testReadingColumn() {
        // Portrait windows use the whole width.
        XCTAssertEqual(SportsSky.contentWidth(390, landscape: false), 390)
        // Landscape: about half the width, between 300 and 520 points.
        XCTAssertEqual(SportsSky.contentWidth(844, landscape: true), 439)
        XCTAssertEqual(SportsSky.contentWidth(1366, landscape: true), 520)
        XCTAssertEqual(SportsSky.contentWidth(500, landscape: true), 300)
        XCTAssertEqual(SportsSky.contentWidth(280, landscape: true), 280)
    }
}
