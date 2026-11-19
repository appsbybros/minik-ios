import SwiftUI

/// iOS payment model (CLAUDE.md): "Unlock the full game", on the app's page scaffold with its sky buttons. It covers
/// the current page (`RootView`), so Back returns to the same page with its choices kept. Buying goes through the
/// grown-up gate (as Android's purchases do); Restore does not need it.
struct SpudUnlockScreen: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SpudStore

    var body: some View {
        let owned = store.ownsFullGame
        return AmuduPage(owned ? StoreText.get(.thanksTitle) : StoreText.get(.title), background: model.art.scene(.park),
                         back: { store.closeUnlock() }) {
            if owned {
                Image(uiImage: model.art.ballPreview(.paint))
                    .resizable()
                    .scaledToFit()
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                AmuduLabel(StoreText.get(.thanksBody), size: 20, color: 0xffffdf70)
            } else {
                AmuduParagraph(StoreText.get(.intro), size: 18, color: 0xffa8f7df)
                ForEach([StoreText.Key.featurePlayers, .featureArenas, .featureBalls, .featurePaint, .featureChallenges], id: \.self) { key in
                    AmuduParagraph(StoreText.get(key), size: 17)
                }
                AmuduLabel(StoreText.get(.oneTime), size: 17, color: 0xffffdf70)
                    .padding(.top, 8)
                buyButton
                if let line = statusLine {
                    AmuduParagraph(line, size: 16, color: 0xffd0e4ee)
                }
                AmuduButton(StoreText.get(.restore), color: 0xffb7dcff, enabled: !store.isBusy && store.status != .unconfigured) {
                    Task { await store.restore() }
                }
            }
            AmuduButton(model.tr("Back", "חזרה")) { store.closeUnlock() }
                .padding(.top, 8)
        }
    }

    /// The price from the App Store; without it, a disabled button while it loads, or Load the price again.
    @ViewBuilder private var buyButton: some View {
        if let product = store.product {
            AmuduButton(StoreText.buy(price: product.displayPrice), color: 0xffffd65a, enabled: !store.isBusy) {
                let shop = store
                model.parentGate { Task { await shop.purchase() } }
            }
            .padding(.top, 8)
        } else if store.status == .loading {
            AmuduButton(StoreText.get(.title), color: 0xffffd65a, enabled: false) {}
                .padding(.top, 8)
        } else {
            AmuduButton(StoreText.get(.reload), color: 0xffffd65a, enabled: !store.isBusy && store.status != .unconfigured) {
                Task { await store.reload() }
            }
            .padding(.top, 8)
        }
    }

    private var statusLine: String? {
        if let notice = store.notice {
            switch notice {
            case .pending: return StoreText.get(.pending)
            case .purchaseFailed: return StoreText.get(.purchaseFailed)
            case .restoreFailed: return StoreText.get(.restoreFailed)
            case .nothingToRestore: return StoreText.get(.nothingToRestore)
            }
        }
        switch store.status {
        case .loading: return StoreText.get(.loading)
        case .purchasing, .restoring: return StoreText.get(.working)
        case .unavailable, .unconfigured: return store.product == nil ? StoreText.get(.unavailable) : nil
        case .ready: return nil
        }
    }
}
