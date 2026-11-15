import AppStoreCommerceKit
import Foundation
import StoreKit

/// When a grown-up took Minik Plus's free 7-day Trial product, from the App Store's own records:
/// the same date after a reinstall and on every device of the Apple Account.
protocol MinikFreeWeekStartReading: Sendable {
    func freeWeekStart(for productID: CommerceProductID) async -> Date?
}

struct StoreKitFreeWeekStartReader: MinikFreeWeekStartReading {
    func freeWeekStart(for productID: CommerceProductID) async -> Date? {
        var earliest: Date?
        for await result in Transaction.all {
            // Only a transaction the App Store signed for this device counts.
            guard case .verified(let transaction) = result,
                  transaction.productID == productID.rawValue else {
                continue
            }
            // A restored or re-delivered transaction may carry a later purchase date; the original
            // purchase date never moves.
            let started = min(transaction.purchaseDate, transaction.originalPurchaseDate)
            earliest = min(earliest ?? started, started)
        }
        return earliest
    }
}
