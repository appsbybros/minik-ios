import SwiftUI
import UIKit

// MARK: Raised-button lettering (Android FamilyButtonAlignment)

/// One text view of a label: where its layout starts in the label, and its shaped lines.
private struct FamilyKitPlacedText: Equatable {
    let origin: CGPoint
    let layout: Text.Layout
}

/// Everything the lettering position depends on; a change re-runs the alignment.
private struct FamilyKitLetteringProbe: Equatable {
    let texts: [FamilyKitPlacedText]
    let size: CGSize
    let cornerRadius: CGFloat
    let pressed: Bool
    let scale: CGFloat
}

/// The measured ink of each text layout, kept until the layout or the screen scale changes (Android
/// caches the raster measurement until the Layout or its text metrics change).
@MainActor
private final class FamilyKitInkCache {
    var layouts: [Text.Layout] = []
    var scale: CGFloat = 0
    var ink: [ClosedRange<CGFloat>?] = []

    func ink(_ texts: [FamilyKitPlacedText], scale: CGFloat) -> [ClosedRange<CGFloat>?] {
        let now = texts.map { $0.layout }
        if now != layouts || scale != self.scale {
            layouts = now
            self.scale = scale
            ink = now.map { FamilyKit.Lettering.inkRows($0, scale: scale) }
        }
        return ink
    }
}

extension FamilyKit {
    /// Android `FamilyButtonAlignment`: the rendered letters of a raised button are centred on its
    /// raised face, not on the face plus its lower lip, then lowered by the owner's 3-point optical
    /// adjustment. The ink is measured from the label's own shaped text (so RTL, fallback fonts, marks
    /// and wrapped labels count the glyphs the button really draws), and the label is moved with a
    /// translation, so the button's size, padding, touch area and background never change.
    @MainActor
    enum Lettering {
        /// Android `useFullRaisedFace`: an app-level choice, set once before the first screen. Off (the
        /// default) the letters centre below the bright upper gloss (`copyTextFaceBounds`); on, on the
        /// whole raised face (`copyFaceBounds`).
        static var fullRaisedFace = false

        /// Android `opticalOffsetPx`: lettering sits 3 points below the centre of its face target.
        static let opticalOffset: CGFloat = 3

        /// Where the middle of the ink belongs in a raised button of this size (not a panel).
        static func target(size: CGSize, cornerRadius: CGFloat, pressed: Bool, pixel: CGFloat) -> CGFloat? {
            let face = fullRaisedFace
                ? SkyLook.faceRect(size: size, radius: cornerRadius, panel: false, pressed: pressed, pixel: pixel)
                : SkyLook.textFaceRect(size: size, radius: cornerRadius, panel: false, pressed: pressed, pixel: pixel)
            if face.width <= 0 || face.height <= 0 { return nil }
            return face.midY + opticalOffset
        }

        /// Android `measureInkMiddle`: draws the layout's lines into a mask and returns the first and last
        /// rows holding ink (alpha at least 16 of 255), in the layout's coordinates; nil without ink.
        static func inkRows(_ layout: Text.Layout, scale: CGFloat) -> ClosedRange<CGFloat>? {
            var bounds = CGRect.null
            for line in layout {
                bounds = bounds.union(line.typographicBounds.rect)
            }
            if bounds.isNull || bounds.width <= 0 || bounds.height <= 0 { return nil }
            // Room for accents and marks outside the line box.
            let pad = bounds.height.rounded(.up)
            let area = bounds.insetBy(dx: -pad, dy: -pad)
            let width = Int((area.width * scale).rounded(.up)), height = Int((area.height * scale).rounded(.up))
            if width <= 0 || height <= 0 || width > 8192 || height > 4096 { return nil }
            let mask = Canvas { context, _ in
                context.translateBy(x: -area.minX, y: -area.minY)
                for line in layout {
                    context.draw(line)
                }
            }
            .frame(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
            let renderer = ImageRenderer(content: mask)
            renderer.scale = scale
            renderer.isOpaque = false
            guard let image = renderer.cgImage else { return nil }
            let bytesPerRow = width * 4
            var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
            let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                // Core Graphics' origin is at the bottom; flip so row 0 is the top of the image.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            if !drawn { return nil }
            var first = -1, last = -1
            for y in 0..<height {
                let row = y * bytesPerRow
                var x = 3
                while x < bytesPerRow {
                    if pixels[row + x] >= 16 {
                        if first < 0 { first = y }
                        last = y
                        break
                    }
                    x += 4
                }
            }
            if first < 0 { return nil }
            return (area.minY + CGFloat(first) / scale)...(area.minY + CGFloat(last + 1) / scale)
        }
    }

    /// Android `FamilyButtonAlignment.bind`: moves the label's lettering onto the raised face of a
    /// `SkySurface` button background of the same size and corner radius. `SkyButtonStyle` and
    /// `MenuButtonStyle` apply it themselves; apply it to a label (before its `.background`) where an
    /// app draws a raised `SkySurface` button another way, such as a picker on a sky face (Android
    /// `bind(text, surface)`). Labels without text, and panels, are left as they are.
    @MainActor
    struct RaisedLettering: ViewModifier {
        let cornerRadius: CGFloat
        let pressed: Bool
        @State private var shift: CGFloat = 0
        @State private var cache = FamilyKitInkCache()
        @Environment(\.displayScale) private var displayScale

        init(cornerRadius: CGFloat = 18, pressed: Bool = false) {
            self.cornerRadius = cornerRadius
            self.pressed = pressed
        }

        func body(content: Content) -> some View {
            content
                .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { proxy in
                        // Measured before the shift, so moving the letters never feeds back into the measurement.
                        let probe = FamilyKitLetteringProbe(texts: layouts.map { FamilyKitPlacedText(origin: proxy[$0.origin], layout: $0.layout) },
                                                            size: proxy.size, cornerRadius: cornerRadius, pressed: pressed,
                                                            scale: max(displayScale, 1))
                        Color.clear
                            .onChange(of: probe, initial: true) { _, now in
                                align(now)
                            }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .offset(y: shift)
        }

        private func align(_ probe: FamilyKitLetteringProbe) {
            let ink = cache.ink(probe.texts, scale: probe.scale)
            var top = CGFloat.infinity, bottom = -CGFloat.infinity
            for (text, rows) in zip(probe.texts, ink) {
                guard let rows = rows else { continue }
                top = min(top, text.origin.y + rows.lowerBound)
                bottom = max(bottom, text.origin.y + rows.upperBound)
            }
            guard top <= bottom,
                  let target = Lettering.target(size: probe.size, cornerRadius: probe.cornerRadius, pressed: probe.pressed,
                                                pixel: 1 / probe.scale) else {
                if shift != 0 { shift = 0 }
                return
            }
            // Whole device pixels, and no change for less than one (Android ignores under 0.75 px).
            let wanted = ((target - (top + bottom) / 2) * probe.scale).rounded() / probe.scale
            if abs(wanted - shift) >= 1 / probe.scale { shift = wanted }
        }
    }
}
