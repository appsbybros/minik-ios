import SwiftUI

@main
struct MinikApp: App {
    @UIApplicationDelegateAdaptor(MinikAppDelegate.self) private var appDelegate
    private let configuration = ProductConfiguration.configuration(for: .current)

    var body: some Scene {
        WindowGroup {
            #if MINIK_RETRO_PING_PONG
            BounceRootView()
            #elseif MINIK_MATH_WEB
            MinikMathWebRootView()
            #else
            RootView(configuration: configuration)
            #endif
        }
    }
}

extension ProductVariant {
    static var current: ProductVariant {
        #if MINIK_PLUS
        .minikPlus
        #elseif MINIK_PLUS_ENGLISH
        .minikPlusEnglish
        #elseif MINIK_MATH || MINIK_MATH_WEB
        // Minik Math Plus (MINIK_MATH) and the small Minik Math (MINIK_MATH_WEB) are separate
        // apps; each keeps its own local purchase and ad state.
        .minikMath
        #elseif MINIK_PING_PONG || MINIK_RETRO_PING_PONG
        .minikPingPong
        #else
        #error("A Minik product compilation condition must be configured.")
        #endif
    }
}
