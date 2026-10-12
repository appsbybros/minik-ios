import SwiftUI
import UIKit

/// Android ARGB colour literals (0xAARRGGBB) for Core Graphics, UIKit and SwiftUI.
enum SportsPalette {
    static let ink: UInt32 = 0xff163d50
    static let pink: UInt32 = 0xffe91e63
    static let page: UInt32 = 0xffedf8fb

    static func ui(_ argb: UInt32) -> UIColor {
        return UIColor(red: CGFloat((argb >> 16) & 0xff) / 255.0,
                       green: CGFloat((argb >> 8) & 0xff) / 255.0,
                       blue: CGFloat(argb & 0xff) / 255.0,
                       alpha: CGFloat((argb >> 24) & 0xff) / 255.0)
    }

    static func cg(_ argb: UInt32) -> CGColor {
        return ui(argb).cgColor
    }

    static func color(_ argb: UInt32) -> Color {
        return Color(uiColor: ui(argb))
    }
}
