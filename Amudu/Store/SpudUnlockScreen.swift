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
                ForEach([StoreText.Key.featurePlayers, .featureCharacters, .featureArenas, .featureBalls, .featurePaint,
                         .featureChallenges], id: \.self) { key in
                    AmuduParagraph(StoreText.get(key), size: 17)
                }
                AmuduLabel(StoreText.get(.oneTime), size: 17, color: 0xffffdf70)
                    .padding(.top, 8)
                // Bug report 2026-11-22 (2.2): a line about buying sits directly above the yellow button it belongs
                // to; a problem is red. A line about restoring sits under Restore purchases, which stays apart.
                if let line = buyLine {
                    AmuduParagraph(line.text, size: 16, color: line.problem ? 0xffff8a80 : 0xffd0e4ee)
                        .padding(.top, 8)
                        .padding(.bottom, -8)
                }
                buyButton
                // Apple requires a visible way to restore a non-consumable purchase (App Review Guideline 3.1.1):
                // it is how a new device, a reinstall or Family Sharing gets the full game back.
                AmuduButton(StoreText.get(.restore), color: 0xffb7dcff, enabled: !store.isBusy && store.status != .unconfigured) {
                    Task { await store.restore() }
                }
                .padding(.top, 20)
                if let line = restoreLine {
                    AmuduParagraph(line, size: 16, color: store.notice == .restoreFailed ? 0xffff8a80 : 0xffd0e4ee)
                        .padding(.top, -8)
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

    /// The line above the buy button: loading, buying, a purchase answer, or why there is no price.
    private var buyLine: (text: String, problem: Bool)? {
        switch store.notice {
        case .pending: return (StoreText.get(.pending), false)
        case .purchaseFailed:
            // A known reason (no product, purchases turned off, offline) says more than "did not go through".
            let reason = store.problem
            return (reason == .notAnswering ? StoreText.get(.purchaseFailed) : StoreText.problem(reason), true)
        case .restoreFailed, .nothingToRestore, nil: break
        }
        switch store.status {
        case .loading: return (StoreText.get(.loading), false)
        case .purchasing: return (StoreText.get(.working), false)
        case .unconfigured: return (StoreText.get(.productUnavailable), true)
        case .unavailable: return store.product == nil ? (StoreText.problem(store.problem), true) : nil
        case .restoring, .ready: return nil
        }
    }

    /// The line under Restore purchases.
    private var restoreLine: String? {
        switch store.notice {
        case .restoreFailed: return StoreText.get(.restoreFailed)
        case .nothingToRestore: return StoreText.get(.nothingToRestore)
        default: return store.status == .restoring ? StoreText.get(.working) : nil
        }
    }
}
