import Combine
import Foundation

/// Android IntroScreen's limits: Add hides once there are 20 children, and the
/// name field (childNameInput, maxLength 16) takes at most 16 characters.
enum ChildProfileLimits {
    static let maximumChildren = 20
    static let maximumNameLength = 16

    /// The name as it is kept: on one line, trimmed, at most 16 characters.
    static func normalizedName(_ proposedName: String) -> String {
        let singleLine = proposedName
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(maximumNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A child on this device: an entry of Android's ChildrenNames list. The name is
/// stored only on this device and is never part of a leaderboard record.
struct ChildProfile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
}

/// Whose progress the app shows: a child, or the guest that Android keeps in
/// slot -1 while no child exists (the progress the app had before children).
enum ChildProfileLearner: Hashable, Sendable {
    case guest
    case child(UUID)

    fileprivate var storageID: String {
        switch self {
        case .guest:
            return "guest"
        case .child(let id):
            return id.uuidString
        }
    }

    fileprivate init?(storageID: String) {
        if storageID == "guest" {
            self = .guest
        } else if let id = UUID(uuidString: storageID) {
            self = .child(id)
        } else {
            return nil
        }
    }

    /// The owner of the learner's public Top 20 identity, alias and pending best,
    /// as Android keeps a LeaderboardProfile per child slot. The guest keeps the
    /// identity the app used before child profiles existed.
    var rewardOwnerID: RewardOwnerID {
        switch self {
        case .guest:
            return .localDefault
        case .child(let id):
            return RewardOwnerID(rawValue: "child-" + id.uuidString.lowercased())
        }
    }
}

/// Why a child's name was not saved.
enum ChildProfileNameProblem: Equatable, Sendable {
    case empty
    case duplicate
    case limitReached
}

/// A UserDefaults value that belongs to the child who is playing. Android keys
/// every per-child value by the child's slot (ChildSlotKeys); here the app's
/// repositories keep reading and writing their usual keys, and the store puts
/// the chosen child's values in place.
struct ChildProfileStoredKey: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case data
        case string
        case integer
        case bool
    }

    let name: String
    let kind: Kind

    /// The per-child keys of the Language apps, with the repository that owns
    /// each. A new per-child value needs its key here. The language on screen
    /// (Android's app locale), purchases, ads and reminders stay with the
    /// device, and the public leaderboard keys are named by the learner instead
    /// (rewardOwnerID).
    static func learnerKeys(for product: ProductVariant) -> [ChildProfileStoredKey] {
        let productID = product.rawValue
        return [
            // LocalRewardRepository: points and the current and best streak.
            ChildProfileStoredKey(name: "minik.rewards.v1", kind: .data),
            // LocalProgressRepository: Progress & Statistics.
            ChildProfileStoredKey(name: "minik.activity-progress.v1", kind: .data),
            // LearnedLanguageRepository (Android UserLearningLanguageManager).
            learnedLanguage(for: product),
            // InterfaceLocaleRepository's learner choice (Android userHostingLang):
            // the interface language chosen for this learner in the Parent Area.
            ChildProfileStoredKey(name: InterfaceLocaleRepository.learnerChoiceKey(for: product), kind: .string),
            // EncouragementPreferenceRepository (Android ShouldPlayGesture).
            ChildProfileStoredKey(name: "minik.encouragement-enabled.v1.\(productID)", kind: .bool),
            // LanguageParentLevelSettingsRepository (Android userLevel, KEY_AUTO, userLevel_SOCCER).
            ChildProfileStoredKey(name: "minik.language-levels.v1.\(productID).mode", kind: .string),
            ChildProfileStoredKey(name: "minik.language-levels.v1.\(productID).words", kind: .string),
            ChildProfileStoredKey(name: "minik.language-levels.v1.\(productID).soccer", kind: .string),
            // LanguageAutoProgressRepository (Android userLevelRamp and the word counters).
            ChildProfileStoredKey(name: "minik.language-auto-progress.v1.\(productID).local-default", kind: .data),
            // TicTacToePreferences (Android userLevel_TTT_, ttt_auto and alreadySaidHowToPlay).
            ChildProfileStoredKey(name: "minik.tic-tac-toe.selected-level", kind: .string),
            ChildProfileStoredKey(name: "minik.tic-tac-toe.adaptive-state", kind: .data),
            ChildProfileStoredKey(name: "minik.tic-tac-toe.first-instruction-spoken", kind: .bool),
            // SoccerIntroductionRepository (Android numOfTimesShownSoccerIntro).
            ChildProfileStoredKey(name: "minik.languageSoccer.introductionPresentationCount.v1", kind: .integer)
        ]
    }

    static func learnedLanguage(for product: ProductVariant) -> ChildProfileStoredKey {
        ChildProfileStoredKey(name: "minik.learned-language.v1.\(product.rawValue)", kind: .string)
    }

    /// UserDefaultsPublicLeaderboardStateStore's key for this learner.
    static func publicLeaderboardStateKey(for product: ProductVariant, ownerID: RewardOwnerID) -> String {
        "minik.public-leaderboard.v1.\(product.rawValue).\(ownerID.rawValue)"
    }

    /// AndroidCompatibleRecordsIdentityStore's key for this learner.
    static func playerIDKey(for product: ProductVariant, ownerID: RewardOwnerID) -> String {
        "minik.records.player-id.v2.\(product.rawValue).\(ownerID.rawValue)"
    }
}

/// The children on this device, which of them is playing, and that child's
/// progress, as Android IntroScreen keeps them (add, select, delete; iOS adds
/// rename). Everything stays on the device.
///
/// The repositories read the playing child's values from their usual keys. When
/// another learner is chosen, the outgoing learner's values are kept aside under
/// this store's key and the incoming learner's are put in place, the way
/// Android's ChildSlotStorage moves a child's values between slots. A pending
/// marker is saved first, so a launch completes an exchange the app was stopped
/// in the middle of.
@MainActor
final class ChildProfileStore: ObservableObject {
    @Published private(set) var children: [ChildProfile] = []
    @Published private(set) var selectedChildID: UUID?

    let product: ProductVariant
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let learnerKeys: [ChildProfileStoredKey]
    private var state: ChildProfileStoreState
    private var cleanupsInFlight: Set<String> = []

    init(product: ProductVariant, userDefaults: UserDefaults = .standard) {
        self.product = product
        self.userDefaults = userDefaults
        let key = ChildProfileStore.stateKey(for: product)
        storageKey = key
        learnerKeys = ChildProfileStoredKey.learnerKeys(for: product)
        state = ChildProfileStore.loadState(forKey: key, userDefaults: userDefaults)
        finishInterruptedExchange()
        publish()
    }

    /// Completes an exchange a stopped app left half done and says whose values
    /// the repositories read now. The hub calls it before it loads any of them.
    static func activeLearnerAfterRecovery(
        for product: ProductVariant,
        userDefaults: UserDefaults = .standard
    ) -> ChildProfileLearner {
        ChildProfileStore(product: product, userDefaults: userDefaults).activeLearner
    }

    var activeLearner: ChildProfileLearner {
        guard let selected = state.selectedChildID else { return .guest }
        return .child(selected)
    }

    var selectedChild: ChildProfile? {
        guard let selectedChildID else { return nil }
        return children.first { $0.id == selectedChildID }
    }

    var canAddChild: Bool {
        state.children.count < ChildProfileLimits.maximumChildren
    }

    /// Android's Save in add mode: the new child is added and chosen, and starts
    /// with no points or progress (ChildSlotStorage.clearSlot). The values of
    /// the learner who played until now, the guest's too, are kept aside for
    /// them. Like saveLanguagesForNewUser, the new child keeps the learned
    /// language in use; it has no interface language of its own until one is
    /// chosen for it in the Parent Area, so the language on screen stays.
    @discardableResult
    func addChild(named proposedName: String) -> ChildProfileNameProblem? {
        let name = ChildProfileLimits.normalizedName(proposedName)
        if let problem = nameProblem(name, excluding: nil) {
            return problem
        }
        guard canAddChild else { return .limitReached }
        let child = ChildProfile(id: UUID(), name: name, createdAt: Date())
        var startingValues: [String: Any] = [:]
        let learnedLanguage = ChildProfileStoredKey.learnedLanguage(for: product)
        if let language = learnedLanguageInUse() {
            startingValues[learnedLanguage.name] = language
        }
        writeArchive(startingValues, for: .child(child.id))
        state.children.append(child)
        exchange(to: .child(child.id), keepingOutgoingValues: true)
        return nil
    }

    /// iOS only: Android cannot rename a child. The child's progress is unchanged.
    @discardableResult
    func renameChild(_ id: UUID, to proposedName: String) -> ChildProfileNameProblem? {
        guard let index = state.children.firstIndex(where: { $0.id == id }) else { return nil }
        let name = ChildProfileLimits.normalizedName(proposedName)
        if let problem = nameProblem(name, excluding: id) {
            return problem
        }
        state.children[index].name = name
        saveState()
        publish()
        return nil
    }

    /// Android's child spinner: the chosen child's points, levels and progress
    /// replace the previous child's.
    func selectChild(_ id: UUID) {
        guard id != state.selectedChildID,
              state.children.contains(where: { $0.id == id }) else { return }
        exchange(to: .child(id), keepingOutgoingValues: true)
    }

    /// Android's Delete: the child and all of its values are removed, and the
    /// first remaining child plays, or the guest when none is left. Its public
    /// Top 20 records are deleted afterwards (beginPublicRecordCleanups).
    func deleteChild(_ id: UUID) {
        guard let index = state.children.firstIndex(where: { $0.id == id }) else { return }
        state.children.remove(at: index)
        let deleted = ChildProfileLearner.child(id)
        schedulePublicRecordCleanup(for: deleted.rewardOwnerID)
        if id == state.selectedChildID {
            let next: ChildProfileLearner
            if let first = state.children.first {
                next = .child(first.id)
            } else {
                next = .guest
            }
            // The deleted child's values in place are replaced, not kept.
            exchange(to: next, keepingOutgoingValues: false)
        } else {
            saveState()
            publish()
        }
        removeArchive(for: deleted)
    }

    /// Deleted children whose public records are still to be deleted, except
    /// those already being deleted.
    func beginPublicRecordCleanups() -> [RewardOwnerID] {
        var owners: [RewardOwnerID] = []
        for cleanup in state.publicRecordCleanups {
            let ownerRawValue = cleanup.ownerRawValue
            guard !ownerRawValue.isEmpty, !cleanupsInFlight.contains(ownerRawValue) else { continue }
            cleanupsInFlight.insert(ownerRawValue)
            owners.append(RewardOwnerID(rawValue: ownerRawValue))
        }
        return owners
    }

    /// Records the outcome of a deletion started by beginPublicRecordCleanups.
    /// As Android's outbox keeps a deleted child's deletion pending until it
    /// succeeds (LeaderboardState.requestDelete, RecordsDetails.retryPending), a
    /// failed deletion is tried again later. Once the records are deleted, the
    /// deleted child's leaderboard identity is removed from the device too.
    func finishPublicRecordCleanup(for ownerID: RewardOwnerID, deleted: Bool) {
        cleanupsInFlight.remove(ownerID.rawValue)
        guard deleted,
              let index = state.publicRecordCleanups.firstIndex(where: {
                  $0.ownerRawValue == ownerID.rawValue
              }) else { return }
        state.publicRecordCleanups.remove(at: index)
        removePublicLeaderboardValues(of: ownerID)
        saveState()
    }

    // MARK: - Names

    /// Android refuses two children with the same name, ignoring case.
    private func nameProblem(_ name: String, excluding id: UUID?) -> ChildProfileNameProblem? {
        if name.isEmpty {
            return .empty
        }
        let isTaken = state.children.contains { child in
            child.id != id && child.name.caseInsensitiveCompare(name) == .orderedSame
        }
        return isTaken ? .duplicate : nil
    }

    // MARK: - Exchanging learners

    /// Makes `target` the learner whose values the repositories read. The
    /// pending marker is saved before any value moves.
    private func exchange(to target: ChildProfileLearner, keepingOutgoingValues: Bool) {
        if keepingOutgoingValues {
            writeArchive(liveValues(), for: activeLearner)
        }
        state.pendingLearnerID = target.storageID
        saveState()
        completeExchange(to: target)
    }

    /// Puts the target's kept values in place (none for a new child) and forgets
    /// them. Doing it again changes nothing, so a launch can repeat it.
    private func completeExchange(to target: ChildProfileLearner) {
        setLiveValues(archive(for: target))
        switch target {
        case .guest:
            state.selectedChildID = nil
        case .child(let id):
            state.selectedChildID = id
        }
        state.pendingLearnerID = nil
        saveState()
        removeArchive(for: target)
        publish()
    }

    private func finishInterruptedExchange() {
        if let pendingID = state.pendingLearnerID {
            if let target = ChildProfileLearner(storageID: pendingID), isKnown(target) {
                completeExchange(to: target)
                return
            }
            state.pendingLearnerID = nil
            saveState()
        }
        // A selection that names no child: the values in place stay where they
        // are and belong to the first child, or to the guest.
        if let selected = state.selectedChildID,
           !state.children.contains(where: { $0.id == selected }) {
            state.selectedChildID = state.children.first?.id
            saveState()
        }
    }

    private func isKnown(_ learner: ChildProfileLearner) -> Bool {
        switch learner {
        case .guest:
            return true
        case .child(let id):
            return state.children.contains { $0.id == id }
        }
    }

    // MARK: - Values in place

    private func liveValues() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in learnerKeys {
            if let value = liveValue(for: key) {
                values[key.name] = value
            }
        }
        return values
    }

    private func liveValue(for key: ChildProfileStoredKey) -> Any? {
        guard let stored = userDefaults.object(forKey: key.name) else { return nil }
        return Self.checked(stored, as: key.kind)
    }

    /// The learned language the playing learner has now (Android's
    /// DeviceStatusManager.learningLanguage): the stored one, or else the app's
    /// default for the language on screen, as the hub reads it.
    private func learnedLanguageInUse() -> String? {
        let defaults = userDefaults
        let repository = LearnedLanguageRepository(
            userDefaults: defaults,
            interfaceLocale: { variant in
                InterfaceLocaleRepository(userDefaults: defaults).load(for: variant)
            }
        )
        return repository.load(for: ProductConfiguration.configuration(for: product))?.rawValue
    }

    /// Every per-child key takes the learner's kept value, or is removed when
    /// the learner has none, so a new child starts clean.
    private func setLiveValues(_ values: [String: Any]) {
        for key in learnerKeys {
            if let stored = values[key.name], let value = Self.checked(stored, as: key.kind) {
                userDefaults.set(value, forKey: key.name)
            } else {
                userDefaults.removeObject(forKey: key.name)
            }
        }
    }

    private static func checked(_ value: Any, as kind: ChildProfileStoredKey.Kind) -> Any? {
        switch kind {
        case .data:
            return value as? Data
        case .string:
            return value as? String
        case .integer:
            return (value as? NSNumber)?.intValue
        case .bool:
            return (value as? NSNumber)?.boolValue
        }
    }

    // MARK: - Kept values

    private func archiveKey(for learner: ChildProfileLearner) -> String {
        storageKey + ".archive." + learner.storageID
    }

    private func archive(for learner: ChildProfileLearner) -> [String: Any] {
        userDefaults.dictionary(forKey: archiveKey(for: learner)) ?? [:]
    }

    private func writeArchive(_ values: [String: Any], for learner: ChildProfileLearner) {
        userDefaults.set(values, forKey: archiveKey(for: learner))
    }

    private func removeArchive(for learner: ChildProfileLearner) {
        userDefaults.removeObject(forKey: archiveKey(for: learner))
    }

    // MARK: - Public leaderboard identity of deleted children

    /// A child that never published has nothing public: its leaderboard values
    /// go at once. Otherwise its records are deleted first.
    private func schedulePublicRecordCleanup(for ownerID: RewardOwnerID) {
        let playerIDKey = ChildProfileStoredKey.playerIDKey(for: product, ownerID: ownerID)
        guard userDefaults.object(forKey: playerIDKey) != nil else {
            removePublicLeaderboardValues(of: ownerID)
            return
        }
        guard !state.publicRecordCleanups.contains(where: { $0.ownerRawValue == ownerID.rawValue }) else { return }
        state.publicRecordCleanups.append(ChildProfilePublicRecordCleanup(ownerRawValue: ownerID.rawValue))
    }

    private func removePublicLeaderboardValues(of ownerID: RewardOwnerID) {
        userDefaults.removeObject(forKey: ChildProfileStoredKey.publicLeaderboardStateKey(for: product, ownerID: ownerID))
        userDefaults.removeObject(forKey: ChildProfileStoredKey.playerIDKey(for: product, ownerID: ownerID))
    }

    // MARK: - Persistence

    private static func stateKey(for product: ProductVariant) -> String {
        "minik.child-profiles.v1.\(product.rawValue)"
    }

    private static func loadState(forKey key: String, userDefaults: UserDefaults) -> ChildProfileStoreState {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ChildProfileStoreState.self, from: data),
              decoded.schemaVersion == ChildProfileStoreState.currentSchemaVersion else {
            return ChildProfileStoreState.empty
        }
        return decoded
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func publish() {
        children = state.children
        selectedChildID = state.selectedChildID
    }
}

/// The store's saved form.
private struct ChildProfileStoreState: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var children: [ChildProfile]
    var selectedChildID: UUID?
    /// The learner whose values are being put in place.
    var pendingLearnerID: String?
    var publicRecordCleanups: [ChildProfilePublicRecordCleanup]

    static var empty: ChildProfileStoreState {
        ChildProfileStoreState(
            schemaVersion: currentSchemaVersion,
            children: [],
            selectedChildID: nil,
            pendingLearnerID: nil,
            publicRecordCleanups: []
        )
    }
}

/// A deleted child whose public Top 20 records are still to be deleted. An
/// earlier saved form also counted failed attempts; decoding ignores that count.
private struct ChildProfilePublicRecordCleanup: Codable, Hashable {
    let ownerRawValue: String
}
