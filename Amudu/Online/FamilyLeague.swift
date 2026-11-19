import Foundation
import UIKit
#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
#endif

/// Android `LeagueStandings` (FamilyLeague.kt): a win earns 3 points; ties are ordered by fewer penalty points, then
/// by name. Absent members keep their totals.
enum LeagueStandings {
    struct Row {
        let member: Member
        let points: Int
        let wins: Int
        let penalties: Int
        let games: Int
        let nicknames: [String]
    }

    static func rows(_ data: Node) -> [Row] {
        let members = AmuduCodec.node(data["members"])
        let rounds = AmuduCodec.node(data["rounds"])
        // Android iterates its decoded maps in their own order; Swift dictionaries have none, so keys are taken in
        // UTF-16 order (the final sort decides the table; only equal rows keep this order).
        let roundKeys = rounds.keys.sorted(by: Kotlin.less)
        let rows: [Row] = members.keys.sorted(by: Kotlin.less).map { id in
            let played: [Node] = roundKeys.compactMap { key in
                let participants = AmuduCodec.node(AmuduCodec.node(rounds[key])["participants"])
                guard let raw = participants[id], !AmuduCodec.isNull(raw) else { return nil }
                return AmuduCodec.node(raw)
            }
            let wins = played.filter { $0.flag("won") }.count
            var nicknames: [String] = []
            for round in played {
                for item in AmuduCodec.items(round["nicknames"]) {
                    let text = AmuduCodec.text(item)
                    if !nicknames.contains(text) { nicknames.append(text) }
                }
            }
            return Row(member: AmuduCodec.readMember(AmuduCodec.node(members[id])), points: wins * 3, wins: wins,
                       penalties: played.reduce(0) { $0 + Kotlin.toInt($1.num("penalties")) }, games: played.count, nicknames: nicknames)
        }
        return Kotlin.stableSorted(rows) { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.penalties != b.penalties { return a.penalties < b.penalties }
            return Kotlin.less(a.member.name, b.member.name)
        }
    }
}

/// Android `FamilyLeague`: an invitation-only roster. Game rooms are temporary; the league and results survive them.
/// Realtime Database paths `minikAmudu/leagues/{hostUid}`, `leagueCodes/{CODE}`, `leagueUsers/{uid}`,
/// `leagueInvites/{uid}` and `rooms/{CODE}` (the league's fixed room code) are identical to Android.
/// The page itself is `FamilyLeagueScreen`; `onShow` brings it forward (Android `a.page(...)`).
@MainActor final class FamilyLeague: ObservableObject {
    enum Page { case loading, landing, league }

    @Published private(set) var page: Page = .loading
    @Published private(set) var data: Node = [:]
    @Published var joinVisible = false
    @Published var joinInput = ""
    @Published var deleteVisible = false
    /// Set by the app: shows the league page (Android `a.page(tr("Family league", ...))`).
    var onShow: (@MainActor () -> Void)?

    private weak var model: AppModel?
    private(set) var id = ""
    private var uid = ""
    private var visible = false

    var code: String { return data.str("code") }
    var isHost: Bool { return uid == id }
    var botIds: [String] {
        let members = AmuduCodec.node(data["members"])
        return Kotlin.stableSorted(members.values.map { AmuduCodec.node($0) }.filter { $0.flag("bot") }) {
            (Int($0.str("slot")) ?? 0) < (Int($1.str("slot")) ?? 0)
        }.map { $0.str("character") }
    }
    var rows: [LeagueStandings.Row] { return LeagueStandings.rows(data) }
    var activeRoom: String { return data.str("activeRoom") }

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
    private var db: Database?
    private var ref: DatabaseReference?
    private var handle: UInt?
    #endif

    init(model: AppModel) {
        self.model = model
    }

    private func tr(_ en: String, _ he: String) -> String {
        return GameText.t(en, he, hebrew: AppText.language == "he")
    }

    private var hebrew: Bool { return AppText.language == "he" }

    func hide() { visible = false }

    private func show(_ next: Page) {
        page = next
        onShow?()
    }

    /// Android `landing()`.
    private func landing() {
        if !visible { return }
        show(.landing)
    }

    /// Android `render()`.
    private func render() {
        show(.league)
    }

    func config() -> GameConfig? {
        return try? AmuduCodec.readConfig(AmuduCodec.node(data["config"]))
    }

    /// Android `Copy code`.
    func copyCode() {
        UIPasteboard.general.string = code
        model?.status(tr("Code copied.", "הקוד הועתק."))
    }

    /// The join dialog's "Join" (Android `join(input.text.toString().trim().uppercase())`).
    func confirmJoin() {
        join(Kotlin.trim(joinInput).uppercased())
        joinInput = ""
    }

    private func error(_ e: Error) {
        model?.status(OnlineErrors.message(e))
    }

    // MARK: Pending offline league results (Android SharedPreferences "league-pending")

    private static let pendingKey = "amudu." + "league-pending"

    private static func pending() -> [String: String] {
        return (UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String]) ?? [:]
    }

    private static func setPending(_ value: [String: String]) {
        UserDefaults.standard.set(value, forKey: pendingKey)
    }

    /// Android `resultRow(e)`.
    private static func resultRow(_ e: AmuduEngine) -> Node? {
        guard let outcome = e.result else { return nil }
        var participants: Node = [:]
        for a in e.actors {
            participants[a.member.id] = ["member": AmuduCodec.member(a.member), "penalties": a.penalties,
                                         "won": outcome.winners.contains(a.member.id), "nicknames": a.suffixes] as Node
        }
        return ["participants": participants, "at": Int64(Date().timeIntervalSince1970 * 1000)]
    }

    #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)

    func open() {
        visible = true
        show(.loading)
        guard let link = OnlineRoom.connection() else {
            model?.status(tr("Online activation is pending.", "הפעלת האונליין עדיין בהמתנה."))
            return
        }
        db = link.database
        let auth = link.auth
        let load: @MainActor () -> Void = { [weak self] in
            guard let self, let database = self.db, let user = auth.currentUser else { return }
            self.uid = user.uid
            FamilyLeague.flushPending(database)
            let me = self.uid
            Task { @MainActor [weak self] in
                do {
                    let s = try await database.reference(withPath: "minikAmudu/leagueUsers/\(me)").getData()
                    guard let self else { return }
                    guard let owned = s.value as? String else {
                        self.landing()
                        return
                    }
                    let h = try await database.reference(withPath: "minikAmudu/leagues/\(owned)/host").getData()
                    if h.exists() {
                        self.attach(owned)
                    } else {
                        _ = try await database.reference(withPath: "minikAmudu/leagueUsers/\(me)").removeValue()
                        self.landing()
                    }
                } catch {
                    self?.error(error)
                }
            }
        }
        if auth.currentUser == nil {
            Task { @MainActor [weak self] in
                do {
                    _ = try await auth.signInAnonymously()
                    load()
                } catch {
                    self?.error(error)
                }
            }
        } else {
            load()
        }
    }

    func create(_ cfg: GameConfig, _ bots: [String], _ identity: Member) {
        guard let database = db else { return }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let invite = String((0..<6).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
        let me = uid
        claimIndex(me) { [weak self] in
            guard let self else { return }
            self.id = me
            var memberNodes: Node = [:]
            var slots: Node = [:]
            var hostNode = AmuduCodec.member(identity.copy(id: me))
            hostNode["slot"] = "0"
            memberNodes[me] = hostNode
            slots["0"] = me
            for (i, b) in bots.enumerated() {
                let bid = "house_\(b)"
                var n = AmuduCodec.member(Member(bid, b, AmuduCharacters.get(b).name(hebrew: self.hebrew), bot: true, hebrew: self.hebrew))
                n["slot"] = String(i + 1)
                memberNodes[bid] = n
                slots[String(i + 1)] = bid
            }
            let leagueRef = database.reference(withPath: "minikAmudu/leagues/\(me)")
            let roster = memberNodes
            let seats = slots
            Task { @MainActor [weak self] in
                do {
                    let existing = try await leagueRef.getData()
                    guard let self else { return }
                    if existing.exists() {
                        self.visible = true
                        self.attach(me)
                        return
                    }
                    let initial: [String: Any] = ["host": me, "code": invite, "createdAt": ServerValue.timestamp(),
                                                  "config": AmuduCodec.config(cfg), "members": roster, "slots": seats]
                    let codeRef = database.reference(withPath: "minikAmudu/leagueCodes/\(invite)")
                    codeRef.runTransactionBlock({ d in
                        if let current = d.value, !(current is NSNull) { return TransactionResult.abort() }
                        d.value = me
                        return TransactionResult.success(withValue: d)
                    }, andCompletionBlock: { [weak self] e, ok, _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            if let e {
                                self.error(e)
                                return
                            }
                            if !ok {
                                self.create(cfg, bots, identity)
                                return
                            }
                            leagueRef.setValue(initial) { [weak self] failure, _ in
                                MainActor.assumeIsolated {
                                    guard let self else { return }
                                    if let failure {
                                        codeRef.removeValue()
                                        self.error(failure)
                                    } else {
                                        self.visible = true
                                        self.attach(me)
                                    }
                                }
                            }
                        }
                    })
                } catch {
                    self?.error(error)
                }
            }
        }
    }

    private func claimIndex(_ target: String, _ done: @escaping @MainActor () -> Void) {
        guard let database = db else { return }
        database.reference(withPath: "minikAmudu/leagueUsers/\(uid)").runTransactionBlock({ d in
            if let current = d.value, !(current is NSNull), (current as? String) != target { return TransactionResult.abort() }
            d.value = target
            return TransactionResult.success(withValue: d)
        }, andCompletionBlock: { [weak self] e, ok, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let e {
                    self.error(e)
                } else if !ok {
                    self.model?.status(self.tr("You already belong to a family league.", "כבר יש לכם ליגה משפחתית."))
                } else {
                    done()
                }
            }
        })
    }

    private func join(_ invite: String) {
        guard let database = db else { return }
        // Kotlin `invite.matches(Regex("[A-Z2-9]{6}"))`.
        let valid = invite.unicodeScalars.count == 6 &&
            invite.unicodeScalars.allSatisfy { (0x41...0x5A).contains($0.value) || (0x32...0x39).contains($0.value) }
        if !valid {
            model?.status(tr("Enter the six-character room code.", "הזינו קוד חדר בן שישה תווים."))
            return
        }
        let me = uid
        Task { @MainActor [weak self] in
            do {
                let s = try await database.reference(withPath: "minikAmudu/leagueCodes/\(invite)").getData()
                guard let self else { return }
                guard let target = s.value as? String else {
                    self.model?.status(self.tr("Room not found.", "החדר לא נמצא."))
                    return
                }
                self.claimIndex(target) { [weak self] in
                    guard let self, let identity = self.model?.leagueIdentity() else { return }
                    let member = identity.copy(id: me)
                    Task { @MainActor [weak self] in
                        do {
                            let m = try await database.reference(withPath: "minikAmudu/leagues/\(target)/members/\(me)").getData()
                            guard let self else { return }
                            if m.exists() {
                                self.attach(target)
                                return
                            }
                            _ = try await database.reference(withPath: "minikAmudu/leagueInvites/\(me)").setValue(invite)
                            self.joinSeat(target, member, 0)
                        } catch {
                            self?.error(error)
                        }
                    }
                }
            } catch {
                self?.error(error)
            }
        }
    }

    private func joinSeat(_ target: String, _ me: Member, _ slot: Int) {
        guard let database = db else { return }
        let user = uid
        let userIndex = database.reference(withPath: "minikAmudu/leagueUsers/\(user)")
        if slot >= 10 {
            userIndex.removeValue()
            model?.status(tr("This room is full.", "החדר מלא."))
            return
        }
        let seat = database.reference(withPath: "minikAmudu/leagues/\(target)/slots/\(slot)")
        seat.runTransactionBlock({ d in
            if let current = d.value, !(current is NSNull), (current as? String) != user { return TransactionResult.abort() }
            d.value = user
            return TransactionResult.success(withValue: d)
        }, andCompletionBlock: { [weak self] err, ok, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let err {
                    userIndex.removeValue()
                    self.error(err)
                    return
                }
                if !ok {
                    self.joinSeat(target, me, slot + 1)
                    return
                }
                var n = AmuduCodec.member(me)
                n["slot"] = String(slot)
                database.reference(withPath: "minikAmudu/leagues/\(target)/members/\(user)").setValue(n) { [weak self] e, _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let e {
                            seat.removeValue()
                            userIndex.removeValue()
                            self.error(e)
                        } else {
                            self.attach(target)
                        }
                    }
                }
            }
        })
    }

    /// A fire-and-forget removal from a synchronous context (the Firebase SDK also offers an async overload).
    private func forget(_ path: String) {
        db?.reference(withPath: path).removeValue()
    }

    private func detach() {
        if let handle, let ref { ref.removeObserver(withHandle: handle) }
        handle = nil
    }

    private func attach(_ target: String) {
        guard let database = db else { return }
        detach()
        id = target
        let r = database.reference(withPath: "minikAmudu/leagues/\(target)")
        ref = r
        let me = uid
        handle = r.observe(.value, with: { [weak self] s in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !s.exists() {
                    database.reference(withPath: "minikAmudu/leagueUsers/\(me)").removeValue()
                    self.id = ""
                    self.data = [:]
                    self.landing()
                    return
                }
                self.data = AmuduCodec.node(s.value)
                if self.visible { self.render() }
            }
        }, withCancel: { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor [weak self] in
                    do {
                        let h = try await database.reference(withPath: "minikAmudu/leagues/\(target)/host").getData()
                        guard let self else { return }
                        if !h.exists() {
                            self.forget("minikAmudu/leagueUsers/\(me)")
                            self.id = ""
                            self.data = [:]
                            self.landing()
                        } else {
                            self.error(e)
                        }
                    } catch {
                        self?.error(e)
                    }
                }
            }
        })
    }

    func start(_ cfg: GameConfig) {
        if !isHost { return }
        guard let database = db, let r = ref else { return }
        let roomCode = code
        let leagueId = id
        Task { @MainActor [weak self] in
            do {
                let s = try await database.reference(withPath: "minikAmudu/rooms/\(roomCode)/meta").getData()
                guard let self else { return }
                if s.exists() {
                    self.model?.status(self.tr("The current round is still open. Join it before starting another.", "המשחק הנוכחי עדיין פתוח. הצטרפו אליו לפני פתיחת משחק נוסף."))
                    self.visible = true
                    self.render()
                    return
                }
                _ = try await r.child("config").setValue(AmuduCodec.config(cfg))
                self.model?.openLeagueRoom(roomCode, leagueId, true, cfg)
            } catch {
                self?.error(error)
            }
        }
    }

    func clearActive() {
        if isHost { ref?.child("activeRoom").removeValue() }
    }

    func roomCreated() {
        ref?.child("activeRoom").setValue(code)
    }

    func recordOffline(_ e: AmuduEngine) {
        if isHost, let database = db { FamilyLeague.record(database, id, e, error: { [weak self] in self?.error($0) }) }
    }

    func delete() {
        guard let database = db else { return }
        let roomCode = code
        let leagueId = id
        let me = uid
        Task { @MainActor [weak self] in
            do {
                let s = try await database.reference(withPath: "minikAmudu/rooms/\(roomCode)/meta").getData()
                guard let self else { return }
                if s.exists() {
                    self.model?.status(self.tr("Finish the current round before deleting the league.", "סיימו את המשחק הנוכחי לפני מחיקת הליגה."))
                    return
                }
                let update: [AnyHashable: Any] = ["leagues/\(leagueId)": NSNull(), "leagueCodes/\(roomCode)": NSNull(),
                                                  "leagueUsers/\(me)": NSNull(), "leagueInvites/\(me)": NSNull()]
                _ = try await database.reference(withPath: "minikAmudu").updateChildValues(update)
                self.id = ""
                self.data = [:]
                self.landing()
            } catch {
                self?.error(error)
            }
        }
    }

    func close() {
        hide()
        detach()
    }

    /// Android `FamilyLeague.recordLocal`: an offline league round is kept until the league accepts it.
    static func recordLocal(_ model: AppModel, _ id: String, _ e: AmuduEngine) {
        guard let row = resultRow(e) else { return }
        let key = id + "/" + e.id
        guard JSONSerialization.isValidJSONObject(row), let data = try? JSONSerialization.data(withJSONObject: row),
              let json = String(data: data, encoding: .utf8) else { return }
        var stored = pending()
        stored[key] = json
        setPending(stored)
        guard let link = OnlineRoom.connection() else { return }
        let database = link.database
        if link.auth.currentUser == nil {
            let auth = link.auth
            Task { @MainActor [weak model] in
                do {
                    _ = try await auth.signInAnonymously()
                    flushPending(database)
                } catch {
                    model?.status(OnlineErrors.message(error))
                }
            }
        } else {
            flushPending(database)
        }
    }

    private static func flushPending(_ db: Database) {
        for (key, value) in pending() {
            guard let slash = key.firstIndex(of: "/"),
                  let data = value.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let league = String(key[key.startIndex..<slash])
            let round = String(key[key.index(after: slash)...])
            db.reference(withPath: "minikAmudu/leagues/" + league + "/rounds/" + round).runTransactionBlock({ d in
                if let current = d.value, !(current is NSNull) { return TransactionResult.abort() }
                d.value = row
                return TransactionResult.success(withValue: d)
            }, andCompletionBlock: { err, _, _ in
                MainActor.assumeIsolated {
                    if err == nil {
                        var stored = pending()
                        stored[key] = nil
                        setPending(stored)
                    }
                }
            })
        }
    }

    /// Android `FamilyLeague.record`: the round result, written once under the engine's id.
    static func record(_ db: Database, _ id: String, _ e: AmuduEngine, error: @escaping @MainActor (Error) -> Void = { _ in },
                       done: @escaping @MainActor () -> Void = {}) {
        guard let row = resultRow(e) else { return }
        db.reference(withPath: "minikAmudu/leagues/\(id)/rounds/" + e.id).runTransactionBlock({ d in
            if let current = d.value, !(current is NSNull) { return TransactionResult.abort() }
            d.value = row
            return TransactionResult.success(withValue: d)
        }, andCompletionBlock: { err, _, _ in
            MainActor.assumeIsolated {
                if let err { error(err) } else { done() }
            }
        })
    }

    #else

    /// Builds without the Firebase packages: the league page only says online play is pending.
    func open() {
        visible = true
        show(.loading)
        model?.status(tr("Online activation is pending.", "הפעלת האונליין עדיין בהמתנה."))
    }

    func create(_ cfg: GameConfig, _ bots: [String], _ identity: Member) {}
    private func join(_ invite: String) {}
    func start(_ cfg: GameConfig) {}
    func clearActive() {}
    func roomCreated() {}
    func recordOffline(_ e: AmuduEngine) {}
    func delete() {}
    func close() { hide() }

    static func recordLocal(_ model: AppModel, _ id: String, _ e: AmuduEngine) {
        guard let row = resultRow(e), JSONSerialization.isValidJSONObject(row),
              let data = try? JSONSerialization.data(withJSONObject: row), let json = String(data: data, encoding: .utf8) else { return }
        var stored = pending()
        stored[id + "/" + e.id] = json
        setPending(stored)
    }

    #endif
}
