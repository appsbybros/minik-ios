import Foundation

/// Port of MinikFamilyServices `FamilyDialogStyle.java` (family snapshot 2f75e98).
///
/// Optional host presentation. Does not change actions, gates or message policy.
/// The Java interface carries a static `apply`; a Swift protocol cannot be called through its own name, so the interface
/// is `FamilyDialogStyle.Host` and `FamilyDialogStyle.apply(host, dialog)` keeps the Java call shape.
/// No Triple Shot activity implements it, and its Android callers (FamilyMessages' card and reminder, FamilyAdultGate)
/// are the shared iOS module's own SwiftUI dialogs, which apply the same sky style themselves (see FamilyBridge), so in
/// this app only an AndroidKit AlertDialog passed in explicitly reaches it.
enum FamilyDialogStyle {
    /// Java `interface FamilyDialogStyle { void styleFamilyDialog(AlertDialog dialog); }` (implemented by a host activity).
    protocol Host: AnyObject {
        func styleFamilyDialog(_ dialog: AAlertDialog)
    }

    /// Java `static void apply(Activity host, AlertDialog dialog)`: the host's own style, else `FamilySkyUi.dialog`.
    static func apply(host: AActivity, dialog: AAlertDialog) {
        if let style = host as? FamilyDialogStyle.Host { style.styleFamilyDialog(dialog) }
        else { FamilySkyUi.dialog(dialog: dialog) }
    }
    static func apply(_ host: AActivity, _ dialog: AAlertDialog) { apply(host: host, dialog: dialog) }
}
