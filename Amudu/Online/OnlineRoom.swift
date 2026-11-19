import Foundation

#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase

/// A flag a Firebase transaction block (which runs outside the main actor) can read.
private final class SharedFlag: @unchecked Sendable {
    var value = false
}

/// Android `OnlineRoom`: private Realtime Database rooms under `minikAmudu/rooms/{CODE}`.
/// Paths, field names, enum names, transactions, leases and huddle rules are identical to Android, so iOS and
/// Android phones share rooms. Firebase is used only when this app's GoogleService-Info.plist is bundled.
/// A family-league round uses the league's fixed code (`fixedCode`) and `meta/league` = the league id.
@MainActor final class OnlineRoom {
    static let appName = "minik-amudu-production"
    static let root = "minikAmudu/rooms/"

    struct Connection {
        let auth: Auth
        let database: Database
    }

    private static var connections: [String: Connection] = [:]
    /// Kotlin `openAttempts`: a canceled lookup must not remove the same user's newer successful join.
    private static var openAttempts: [String: String] = [:]

    /// The named Firebase app, created only from a bundled plist for this bundle ID with a database URL (shared with
    /// `FamilyLeague`, as on Android).
    static func connection() -> Connection? {
        if let existing = connections[appName] { return existing }
        let app: FirebaseApp
        if let configured = FirebaseApp.app(name: appName) {
            app = configured
        } else {
            guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: path),
                  let url = options.databaseURL, !url.isEmpty,
                  options.bundleID == Bundle.main.bundleIdentifier else { return nil }
            FirebaseApp.configure(name: appName, options: options)
            guard let created = FirebaseApp.app(name: appName) else { return nil }
            app = created
        }
        let made = Connection(auth: Auth.auth(app: app), database: Database.database(app: app))
        connections[appName] = made
        return made
    }

    private(set) var uid = ""
    /// Android `onOpenFailed`: until the room is joined, every status goes here instead of the page.
    var onOpenFailed: (@MainActor (String) -> Void)?
    private weak var model: AppModel?
    private let identity: Member
    private let cfg: GameConfig
    private let house: [String]
    private let leagueId: String
    private let fixedCode: String
    private var auth: Auth?
    private var db: Database?
    private var room: DatabaseReference?
    private var code = ""
    private var meta: Node = [:]
    private var members: Node = [:]
    private var world: AmuduEngine?
    private weak var view: ArenaView?
    private var closed = false {
        didSet { closedFlag.value = closed }
    }
    private let closedFlag = SharedFlag()
    private var active = true
    /// Android `connected`: the Realtime Database `.info/connected` state.
    private var isConnected = false
    private var authority = false
    private var claiming = false
    private var loading = false
    private var starting = false
    private var resultBusy = false
    private var joined = false
    private let openAttempt = UUID().uuidString.lowercased()
    private var openTimeout: DispatchWorkItem?
    private var status: @MainActor (String) -> Void = { _ in }
    private var listeners: [(DatabaseReference, UInt)] = []
    private var commandsHandle: UInt?
    private var userCommands: [String: UInt] = [:]
    private var pending: [(String, GameCommand)] = []
    private var lastHeartbeat: Int64 = 0
    private var lastPublish: Int64 = 0
    private var signature = ""
    private var latest: Node = [:]
    private var version = 0
    private var applied = -1
    private var received: Int64 = 0
    private var huddleId = ""
    private var huddleMeta: Node = [:]
    private var huddleResult: Node = [:]
    private var huddleWriting = false
    private(set) var huddleSuggestions: [String: String] = [:]
    private(set) var huddleVotes: [String: String] = [:]
    private var reconciling = false
    private var oldMembers: Node = [:]
    private var replacingLeader = false
    private var serverOffset: Int64 = 0
    private var huddleCommitted = false
    private var publishedEvent = 0
    private var deleting = false
    private var disconnectDelete = false
    private var seenResult = false
    private var inflightSnapshots = 0
    private var snapshotBaseline: Node = [:]
    private var snapshotEpoch: Int64 = 0
    private let playback = SnapshotPlayback()
    private let motionPublication = MotionPublication()
    private var publishedHuddle = 0
    private var creatingHuddle = false
    private var nextHuddleAttempt: Int64 = 0
    private var pump: Timer?
    private var clockOpened = false

    init(model: AppModel, identity: Member, config: GameConfig, house: [String], leagueId: String = "", fixedCode: String = "") {
        self.model = model
        self.identity = identity
        self.cfg = config
        self.house = house
        self.leagueId = leagueId
        self.fixedCode = fixedCode
    }

    private func now() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000) + serverOffset
    }

    private func tr(_ en: String, _ he: String) -> String {
        return GameText.t(en, he, hebrew: AppText.language == "he")
    }

    private func node(_ value: Any?) -> Node { return AmuduCodec.node(value) }

    private func slotNumber(_ n: Node) -> Int { return Int(n.str("slot")) ?? 0 }

    private func currentAttempt() -> Bool {
        return OnlineRoom.openAttempts["\(uid)/\(code)"] == openAttempt
    }

    private func markAttempt() {
        OnlineRoom.openAttempts["\(uid)/\(code)"] = openAttempt
    }

    func open(join: String?, onStatus: @escaping @MainActor (String) -> Void) {
        status = { [weak self] text in
            guard let self, !self.closed else { return }
            if !self.joined, let failed = self.onOpenFailed {
                self.openTimeout?.cancel()
                failed(text)
            } else {
                onStatus(text)
            }
        }
        if join != nil {
            openTimeout = afterDelay(15) { [weak self] in
                guard let self, !self.closed, !self.joined else { return }
                self.status(self.tr("Could not connect. Check your connection and try again.", "לא הצלחנו להתחבר. בדקו את החיבור ונסו שוב."))
            }
        }
        guard let link = OnlineRoom.connection() else {
            status(tr("Online activation is pending.", "הפעלת האונליין עדיין בהמתנה."))
            return
        }
        auth = link.auth
        db = link.database
        let connectivity = link.database.reference(withPath: ".info/connected")
        let connectivityHandle = connectivity.observe(.value, with: { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = (snapshot.value as? Bool) == true
                self.view?.networkWaiting = !self.isConnected
                if self.isConnected && !wasConnected && self.active && self.room != nil && !Kotlin.isBlank(self.uid) &&
                    self.members[self.uid] != nil {
                    self.registerPresence()
                    self.snapshotBaseline = [:]
                }
            }
        }, withCancel: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isConnected = false
                self.view?.networkWaiting = true
            }
        })
        listeners.append((connectivity, connectivityHandle))
        if let user = link.auth.currentUser {
            connected(user.uid, join)
            return
        }
        let signIn = link.auth
        Task { @MainActor [weak self] in
            do {
                let result = try await signIn.signInAnonymously()
                self?.connected(result.user.uid, join)
            } catch {
                self?.fail(error)
            }
        }
    }

    private func connected(_ id: String, _ join: String?) {
        if closed { return }
        uid = id
        guard let database = db else { return }
        let clockRef = database.reference(withPath: ".info/serverTimeOffset")
        clockOpened = false
        let handle = clockRef.observe(.value, with: { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.serverOffset = (snapshot.value as? NSNumber)?.int64Value ?? 0
                if !self.clockOpened {
                    self.clockOpened = true
                    if let join { self.enter(join) } else { self.create() }
                }
            }
        }, withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.fail(error)
            }
        })
        listeners.append((clockRef, handle))
    }

    private var inLeague: Bool { return !Kotlin.isBlank(leagueId) }

    private func create() {
        guard let database = db else { return }
        if Kotlin.isBlank(fixedCode) {
            let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
            var made = ""
            for _ in 0..<6 { made.append(alphabet[Int.random(in: 0..<alphabet.count)]) }
            code = made
        } else {
            code = fixedCode
        }
        let r = database.reference(withPath: OnlineRoom.root + code)
        room = r
        markAttempt()
        let stamp = now()
        var roster: [(String, Node)] = []
        var hostNode = AmuduCodec.member(identity.copy(id: uid))
        hostNode["slot"] = "0"
        roster.append((uid, hostNode))
        // A league keeps its own chosen house players; a private room never reuses a human avatar.
        let candidates = inLeague ? house : AmuduCharacters.availableBots(humans: [identity], requested: house)
        let bots = Array(candidates.prefix(max(cfg.participants - 1, 0)))
        for (i, id) in bots.enumerated() {
            let c = AmuduCharacters.get(id)
            let m = Member(inLeague ? "house_\(id)" : "house\(i)", id, c.name(hebrew: identity.hebrew), bot: true, hebrew: identity.hebrew)
            var n = AmuduCodec.member(m)
            n["slot"] = String(i + 1)
            roster.append((m.id, n))
        }
        var memberNodes: Node = [:]
        var slots: Node = [:]
        for (id, n) in roster {
            memberNodes[id] = n
            slots[n.str("slot")] = id
        }
        var metaNode: Node = [:]
        metaNode["host"] = uid
        metaNode["phase"] = "lobby"
        metaNode["leaseUntil"] = stamp + 8000
        metaNode["epoch"] = 1
        metaNode["seed"] = stamp
        metaNode["league"] = leagueId
        metaNode["config"] = AmuduCodec.config(cfg)
        let initial: Node = ["meta": metaNode, "members": memberNodes, "slots": slots]
        r.setValue(initial) { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.fail(error)
                    return
                }
                if self.inLeague { self.model?.leagueRoomCreated() }
                self.listen()
            }
        }
    }

    private func enter(_ value: String) {
        if closed { return }
        guard let database = db else { return }
        if inLeague {
            enterRoom(value)
            return
        }
        let lookup = database.reference(withPath: "minikAmudu/leagueCodes/\(value)")
        Task { @MainActor [weak self] in
            do {
                let found = try await lookup.getData()
                guard let self else { return }
                if found.exists() {
                    self.status(self.tr("This code belongs to a league. Join it from Family league.", "הקוד הזה שייך לליגה. הצטרפו דרך ליגה משפחתית."))
                } else {
                    self.enterRoom(value)
                }
            } catch {
                self?.fail(error)
            }
        }
    }

    private func enterRoom(_ value: String) {
        if closed { return }
        guard let database = db else { return }
        code = value
        let r = database.reference(withPath: OnlineRoom.root + code)
        room = r
        markAttempt()
        let me = uid
        Task { @MainActor [weak self] in
            do {
                let snapshot = try await r.child("meta").getData()
                guard let self, !self.closed else { return }
                if !snapshot.exists() {
                    self.model?.forgetRoom(self.code)
                    self.status(self.tr("Room not found.", "החדר לא נמצא."))
                    return
                }
                self.meta = self.node(snapshot.value)
                if self.node(self.meta["config"]).num("controlsRevision") != 2.0 {
                    self.status(self.tr("Everyone needs the latest SPUD version for these controls and paint balloons.",
                                        "כולם צריכים את הגרסה העדכנית של עמודו בשביל השליטה החדשה ובלוני הצבע."))
                    return
                }
                if self.meta.str("phase") == "finished" {
                    self.model?.expiredRoom(self.code)
                    return
                }
                let required = self.meta.str("league")
                if !Kotlin.isBlank(required) && required != self.leagueId {
                    self.status(self.tr("Join this game through your family league.", "הצטרפו למשחק דרך הליגה המשפחתית."))
                    return
                }
                let mine = try await r.child("members/" + me).getData()
                if mine.exists() {
                    self.listen()
                } else if self.meta.str("phase") != "lobby" {
                    self.status(self.tr("This game has already started.", "המשחק כבר התחיל."))
                } else {
                    self.claimSlot(0)
                }
            } catch {
                self?.fail(error)
            }
        }
    }

    private func claimSlot(_ index: Int) {
        if closed { return }
        guard let r = room else { return }
        if Double(index) >= node(meta["config"]).num("participants", 6.0) {
            status(tr("This room is full.", "החדר מלא."))
            return
        }
        let me = uid
        let closedNow = closedFlag
        r.child("slots/\(index)").runTransactionBlock({ data in
            if closedNow.value { return TransactionResult.abort() }
            if let current = data.value, !(current is NSNull), (current as? String) != me {
                return TransactionResult.abort()
            }
            data.value = me
            return TransactionResult.success(withValue: data)
        }, andCompletionBlock: { [weak self] error, committed, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.closed {
                    if committed && self.currentAttempt() { r.child("slots/\(index)").removeValue() }
                    return
                }
                if let error {
                    self.fail(error)
                    return
                }
                if !committed {
                    self.claimSlot(index + 1)
                    return
                }
                var n = AmuduCodec.member(self.identity.copy(id: me))
                n["slot"] = String(index)
                r.child("members/" + me).setValue(n) { [weak self] failure, _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let failure {
                            self.fail(failure)
                            return
                        }
                        if self.closed {
                            if self.currentAttempt() {
                                r.child("members/\(me)/connected").setValue(false)
                                r.updateChildValues(["members/" + me: NSNull(), "slots/\(index)": NSNull()])
                            }
                        } else {
                            self.listen()
                        }
                    }
                }
            }
        })
    }

    /// Android `registerPresence`: onDisconnect is one-shot, so it is registered again after every restored connection.
    private func registerPresence() {
        guard let r = room else { return }
        let me = uid
        r.child("members/\(me)/connected").onDisconnectSetValue(false) { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.fail(error, "presence")
                    return
                }
                if self.active && !self.closed {
                    r.child("members/" + me).updateChildValues(["connected": true, "motionProtocol": MotionState.VERSION, "gameProtocol": 2])
                }
            }
        }
    }

    private func listen() {
        guard !closed, room != nil else { return }
        joined = true
        openTimeout?.cancel()
        registerPresence()
        watch("meta") { [weak self] n in
            guard let self else { return }
            if n.isEmpty {
                self.model?.expiredRoom(self.code)
                return
            }
            self.meta = n
            self.maintainCleanup()
            self.syncRole()
            self.maybeWorld()
            self.lobby()
        }
        watch("members") { [weak self] n in
            self?.membersChanged(n)
        }
        watch("public") { [weak self] n in
            guard let self else { return }
            if !self.authority && !n.isEmpty {
                self.latest = n
                LagDiagnostics.snapshot(n, self.now())
                self.received = uptimeMs()
                self.version += 1
                self.maybeWorld()
            }
        }
        startPump()
    }

    /// The human members that are connected (Kotlin `members.filter{!bot && connected}.keys`).
    private func connectedHumans() -> Set<String> {
        return Set(members.filter { !node($0.value).flag("bot") && node($0.value).flag("connected") }.map { $0.key })
    }

    private func membersChanged(_ n: Node) {
        let humansElsewhere = n.filter { $0.key != uid && !node($0.value).flag("bot") }
        if oldMembers.isEmpty && !humansElsewhere.isEmpty { model?.sound("connected") }
        if !oldMembers.isEmpty {
            if humansElsewhere.contains(where: { oldMembers[$0.key] == nil }) { model?.sound("connected") }
            let becameReady = humansElsewhere.contains { entry in
                let before = node(oldMembers[entry.key])
                return node(entry.value).flag("ready") && !before.isEmpty && !before.flag("ready")
            }
            if becameReady { model?.sound("ready") }
        }
        let removed = members[uid] != nil && n[uid] == nil
        oldMembers = n
        members = n
        if removed {
            model?.removedFromLobby(code)
            return
        }
        maintainCleanup()
        if authority && !starting && !reconciling && meta.str("phase") == "lobby" {
            let humanArt = n.values.filter { !node($0).flag("bot") }.map { node($0).str("character") }
            let botArt = n.values.filter { node($0).flag("bot") }.map { node($0).str("character") }
            if Kotlin.isBlank(meta.str("league")) && (botArt.contains(where: { humanArt.contains($0) }) || Set(botArt).count != botArt.count) {
                reconcileBots(fillAlone: false) {}
            }
        }
        lobby()
        maybeWorld()
        world?.connectedHumanIds = connectedHumans()
        if authority { applyDepartures() }
        if authority, let w = world {
            for a in w.actors where !a.member.bot && !node(members[a.member.id]).flag("connected") { a.move = V.zero }
        }
    }

    private func watch(_ path: String, _ block: @escaping @MainActor (Node) -> Void) {
        guard let r = room else { return }
        let ref = r.child(path)
        let handle = ref.observe(.value, with: { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self, !self.closed, !self.deleting else { return }
                block(self.node(snapshot.value))
            }
        }, withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.fail(error, path)
            }
        })
        listeners.append((ref, handle))
    }

    private func lobby() {
        if meta.str("phase") != "lobby" || members.isEmpty || closed { return }
        let sig = AmuduCodec.describe(members) + meta.str("host")
        if sig == signature { return }
        signature = sig
        let nodes = Kotlin.stableSorted(members.values.map { node($0) }) { slotNumber($0) < slotNumber($1) }
        let players = nodes.map { AmuduCodec.readMember($0) }
        let ready = Set(members.filter { node($0.value).flag("ready") }.map { $0.key })
        let me = uid
        model?.lobby(code: code, players: players, ready: ready, uid: me, host: authority, onReady: { [weak self] in
            guard let self, let r = self.room else { return }
            r.child("members/\(me)/ready").setValue(true)
        }, onStart: { [weak self] in
            self?.start()
        }, gameConfig: try? AmuduCodec.readConfig(node(meta["config"])))
    }

    /// Android `startWithoutUnready`: the host starts without the humans who are not Ready (they leave the room).
    func startWithoutUnready() {
        if !authority || starting || meta.str("phase") != "lobby" { return }
        guard let r = room else { return }
        let excluded = members.filter { $0.key != uid && !node($0.value).flag("bot") && !node($0.value).flag("ready") }
        if members.count - excluded.count < 2 {
            status(tr("At least 2 players are required to start a game.", "צריך לפחות 2 שחקנים כדי להתחיל משחק."))
            return
        }
        var changes: [AnyHashable: Any] = [:]
        for (id, v) in excluded {
            changes["members/" + id] = NSNull()
            changes["slots/" + node(v).str("slot")] = NSNull()
        }
        let gone = Set(excluded.keys)
        r.updateChildValues(changes) { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.fail(error, "start without waiting players")
                    return
                }
                self.members = self.members.filter { !gone.contains($0.key) }
                self.start()
            }
        }
    }

    private func start() {
        if !authority || starting || meta.str("phase") != "lobby" { return }
        if reconciling {
            status(tr("Updating the house players. Tap Start in a moment.", "מעדכנים את שחקני הבית. לחצו התחלה בעוד רגע."))
            return
        }
        if members.contains(where: { $0.key != uid && !node($0.value).flag("bot") && !node($0.value).flag("ready") }) {
            status(tr("Everyone must be Ready.", "כולם צריכים להיות מוכנים."))
            return
        }
        guard let r = room else { return }
        // Alone with house players: the room is removed and the match is played on this phone.
        if members.values.filter({ !node($0).flag("bot") }).count == 1 {
            let nodes = Kotlin.stableSorted(members.values.map { node($0) }) { slotNumber($0) < slotNumber($1) }
            let roster = nodes.map { AmuduCodec.readMember($0) }
            if roster.count < 2 {
                status(tr("Choose at least one house player.", "בחרו לפחות שחקן בית אחד."))
                return
            }
            starting = true
            deleting = true
            r.removeValue { [weak self] error, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error {
                        self.starting = false
                        self.deleting = false
                        self.fail(error)
                        return
                    }
                    do {
                        let config = try AmuduCodec.readConfig(self.node(self.meta["config"])).with(participants: roster.count)
                        let seed = self.now()
                        let e = try AmuduEngine(members: roster, config: config, seed: seed, id: self.code + "-" + String(self.now()))
                        let me = self.uid
                        let roomCode = self.code
                        let league = self.meta.str("league")
                        self.close(leave: false)
                        self.model?.offlineRoom(e, uid: me, code: roomCode, leagueId: league)
                    } catch {
                        self.starting = false
                        self.deleting = false
                        self.fail(error)
                    }
                }
            }
            return
        }
        starting = true
        reconcileBots(fillAlone: false) { [weak self] in
            guard let self, let r = self.room else { return }
            let me = self.uid
            let lease = self.now() + 8000
            r.child("meta").runTransactionBlock({ d in
                let host = d.childData(byAppendingPath: "host").value as? String
                let phase = d.childData(byAppendingPath: "phase").value as? String
                if host != me || phase != "lobby" { return TransactionResult.abort() }
                d.childData(byAppendingPath: "phase").value = "playing"
                d.childData(byAppendingPath: "leaseUntil").value = lease
                return TransactionResult.success(withValue: d)
            }, andCompletionBlock: { [weak self] error, _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.starting = false
                    if let error { self.fail(error) }
                }
            })
        }
    }

    private func reconcileBots(fillAlone: Bool, done: @escaping @MainActor () -> Void) {
        guard let r = room else { return }
        if !Kotlin.isBlank(meta.str("league")) {
            r.child("members/\(uid)/ready").setValue(true) { [weak self] error, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error {
                        self.starting = false
                        self.fail(error)
                    } else {
                        done()
                    }
                }
            }
            return
        }
        reconciling = true
        let humans = members.values.map { AmuduCodec.readMember(node($0)) }.filter { !$0.bot }
        let bots = Kotlin.stableSorted(members.values.map { node($0) }.filter { $0.flag("bot") }) { slotNumber($0) < slotNumber($1) }
        let capacity = Kotlin.toInt(node(meta["config"]).num("participants", Double(cfg.participants)))
        let desired = (fillAlone && humans.count == 1) ? capacity - 1 : bots.count
        let ids = Array(AmuduCharacters.availableBots(humans: humans, requested: bots.map { $0.str("character") }, fillTo: desired).prefix(max(desired, 0)))
        var update: [AnyHashable: Any] = ["members/" + uid + "/ready": true]
        var used = Set(members.values.map { slotNumber(node($0)) })
        for (i, id) in ids.enumerated() {
            let previous: Node? = i < bots.count ? bots[i] : nil
            let slot: String
            if let previous {
                slot = previous.str("slot")
            } else {
                guard let free = (0..<max(capacity, 0)).first(where: { !used.contains($0) }) else { continue }
                used.insert(free)
                slot = String(free)
            }
            let bid = previous?.str("id") ?? ("houseAuto" + slot)
            let m = Member(bid, id, AmuduCharacters.get(id).name(hebrew: identity.hebrew), bot: true, hebrew: identity.hebrew)
            var n = AmuduCodec.member(m)
            n["slot"] = slot
            update["members/" + bid] = n
            update["slots/" + slot] = bid
        }
        let values = update
        Task { @MainActor [weak self] in
            do {
                _ = try await r.updateChildValues(values)
                let snapshot = try await r.child("members").getData()
                guard let self else { return }
                self.members = self.node(snapshot.value)
                self.reconciling = false
                done()
            } catch {
                guard let self else { return }
                self.starting = false
                self.reconciling = false
                self.fail(error)
            }
        }
    }

    /// Android `applyDepartures`: members who left a started game stop playing.
    private func applyDepartures() {
        for (id, value) in members where node(value).flag("left") { world?.depart(id) }
    }

    /// Android `canFinishGame`: only the host finishes a running shared game.
    func canFinishGame() -> Bool {
        return authority && world != nil && world?.result == nil
    }

    func endGame() {
        if !authority {
            status(tr("Only the room host can finish the game for everyone.", "רק מארח החדר יכול לסיים את המשחק לכולם."))
            return
        }
        world?.finish()
    }

    private func syncRole() {
        let next = meta.str("host") == uid && meta.str("phase") != "finished"
        if next != authority {
            snapshotEpoch += 1
            inflightSnapshots = 0
            snapshotBaseline = [:]
            motionPublication.reset()
            authority = next
            if authority {
                world = nil
                latest = [:]
            } else {
                stopCommands()
                view?.remote = true
            }
            maybeWorld()
        }
    }

    private func maybeWorld() {
        if closed || members.isEmpty || meta.str("phase") == "lobby" || loading { return }
        if world != nil { return }
        if authority {
            guard let r = room else { return }
            loading = true
            Task { @MainActor [weak self] in
                do {
                    let snapshot = try await r.child("checkpoint").getData()
                    guard let self else { return }
                    self.loading = false
                    if self.closed || !self.authority { return }
                    let engine: AmuduEngine
                    if snapshot.exists() {
                        engine = try AmuduCodec.create(self.node(snapshot.value))
                    } else {
                        let nodes = Kotlin.stableSorted(self.members.values.map { self.node($0) }) { self.slotNumber($0) < self.slotNumber($1) }
                        let roster = nodes.map { AmuduCodec.readMember($0) }
                        let config = try AmuduCodec.readConfig(self.node(self.meta["config"])).with(participants: self.members.count)
                        let seed = Kotlin.toLong(self.meta.num("seed"))
                        engine = try AmuduEngine(members: roster, config: config, seed: seed, id: self.code + "-" + String(seed))
                    }
                    self.world = engine
                    engine.onlineHuddles = true
                    for a in engine.actors where !a.member.bot && !self.node(self.members[a.member.id]).flag("connected") { a.move = V.zero }
                    self.watchCommands()
                    self.model?.present(engine, uid: self.uid, network: self)
                } catch {
                    self?.loading = false
                    self?.fail(error)
                }
            }
        } else if !latest.isEmpty && SnapshotGuard.playable(latest) {
            guard let engine = try? AmuduCodec.create(latest) else { return }
            world = engine
            engine.onlineHuddles = true
            model?.present(engine, uid: uid, network: self)
        }
    }

    func attach(_ v: ArenaView) {
        view = v
        v.remote = !authority
        v.networkWaiting = !isConnected
        v.sendCommand = { [weak self] cmd in
            guard let self else { return }
            if self.authority {
                _ = self.world?.command(self.uid, UUID().uuidString.lowercased(), cmd)
                return
            }
            let key: String
            switch cmd {
            case .move: key = "move"
            case .aim: key = "aim"
            default: key = UUID().uuidString.lowercased()
            }
            if let index = self.pending.firstIndex(where: { $0.0 == key }) {
                self.pending[index] = (key, cmd)
            } else {
                self.pending.append((key, cmd))
            }
            if key != "move" && key != "aim" { self.flush() }
        }
        v.remoteUpdate = { [weak self, weak v] in
            guard let self, let v else { return }
            self.remoteUpdate(v)
        }
    }

    /// Guests play the known motion continuously between snapshots (`SnapshotPlayback`); the host alone decides
    /// catches, possession and score.
    private func remoteUpdate(_ v: ArenaView) {
        if !SnapshotGuard.playable(latest) { return }
        let frameNow = uptimeMs()
        let processingAt = DispatchTime.now().uptimeNanoseconds
        if version != applied {
            let serverNow = Double(now())
            playback.accept(v.engine, latest, received, Kotlin.clamp((serverNow - latest.num("publishedAt", serverNow)) / 1000.0, 0.0, 0.30))
            applied = version
        }
        playback.render(v.engine, frameNow)
        let elapsed = DispatchTime.now().uptimeNanoseconds &- processingAt
        LagDiagnostics.processing(Int64(elapsed / 1000))
    }

    private func watchCommands() {
        stopCommands()
        guard let r = room else { return }
        let ref = r.child("commands")
        commandsHandle = ref.observe(.childAdded, with: { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.listenUserCommands(snapshot.key)
            }
        }, withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, self.authority, !self.closed else { return }
                self.fail(error)
            }
        })
    }

    private func listenUserCommands(_ id: String) {
        if userCommands[id] != nil { return }
        guard let r = room else { return }
        let ref = r.child("commands/" + id)
        let handle = ref.observe(.childAdded, with: { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self, self.authority else { return }
                if let cmd = AmuduCodec.readCommand(self.node(snapshot.value)) {
                    _ = self.world?.command(id, snapshot.key, cmd)
                }
                snapshot.ref.removeValue()
            }
        }, withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, self.authority, !self.closed else { return }
                self.fail(error)
            }
        })
        userCommands[id] = handle
    }

    private func stopCommands() {
        guard let r = room else { return }
        if let handle = commandsHandle { r.child("commands").removeObserver(withHandle: handle) }
        commandsHandle = nil
        for (id, handle) in userCommands { r.child("commands/" + id).removeObserver(withHandle: handle) }
        userCommands.removeAll()
    }

    private func flush() {
        if meta.str("phase") != "playing" || world?.result != nil {
            pending.removeAll()
            return
        }
        guard !pending.isEmpty, let r = room else { return }
        // Push keys keep the commands in the order they were given (Android `room.push().key`).
        var update: [String: Any] = [:]
        var types: [String] = []
        for (_, cmd) in pending {
            var n = AmuduCodec.command(cmd)
            let type = n.str("type")
            if !types.contains(type) { types.append(type) }
            n["at"] = ServerValue.timestamp()
            update[r.childByAutoId().key ?? UUID().uuidString.lowercased()] = n
        }
        pending.removeAll()
        let sentAt = uptimeMs()
        LagDiagnostics.sending(update)
        r.child("commands/" + uid).updateChildValues(update) { [weak self] error, _ in
            MainActor.assumeIsolated {
                LagDiagnostics.ack(uptimeMs() - sentAt, command: true)
                if let error { self?.fail(error, "command " + types.joined(separator: ", ")) }
            }
        }
    }

    private func startPump() {
        pump?.invalidate()
        pump = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.cycle()
            }
        }
    }

    private func cycle() {
        guard active, isConnected, let r = room, !meta.isEmpty else { return }
        if meta.str("phase") == "finished" {
            pending.removeAll()
            maintainCleanup()
            return
        }
        let stamp = now()
        if let database = db { LagDiagnostics.upload(database.reference(), uid: uid, host: authority) }
        view?.networkWaiting = !authority && (received == 0 || uptimeMs() - received > 4500)
        if authority && stamp - lastHeartbeat > 2000 {
            lastHeartbeat = stamp
            r.child("meta/leaseUntil").setValue(stamp + 8000)
        }
        if !authority && meta.str("phase") == "playing" && meta.num("leaseUntil") < Double(stamp) && !claiming { claim() }
        flush()
        guard let e = world else { return }
        if authority { applyDepartures() }
        if authority { e.connectedHumanIds = connectedHumans() }
        let event = e.events.last?.id ?? 0
        let interval: Int64 = event > publishedEvent ? 50 : Int64(1000 / e.config.snapshotHz)
        if authority && inflightSnapshots < 4 && stamp - lastPublish >= interval {
            lastPublish = stamp
            publishedEvent = event
            let publishingHuddle = e.phase == .huddle ? e.huddleSerial : 0
            // Older Android/iOS clients retain legacy snapshots until they advertise support.
            let motionReady = members.values.map { node($0) }.filter { !$0.flag("bot") && $0.flag("connected") }
                .allSatisfy { Kotlin.toInt($0.num("motionProtocol")) >= MotionState.VERSION }
            var shared = motionPublication.encode(e, AmuduCodec.shared(e), motionReady)
            shared["publishedAt"] = stamp
            let next: Node = ["public": SnapshotWire.presentation(shared), "checkpoint": AmuduCodec.checkpoint(e, shared: shared)]
            let delta = SnapshotDelta.between(snapshotBaseline, next)
            if JSONSerialization.isValidJSONObject(delta) {
                snapshotBaseline = next
                let epoch = snapshotEpoch
                inflightSnapshots += 1
                let sentAt = uptimeMs()
                LagDiagnostics.sending(delta)
                r.updateChildValues(delta) { [weak self] error, _ in
                    MainActor.assumeIsolated {
                        LagDiagnostics.ack(uptimeMs() - sentAt)
                        guard let self else { return }
                        if epoch == self.snapshotEpoch {
                            if let error {
                                self.snapshotBaseline = [:]
                                self.fail(error, "snapshot")
                            } else {
                                self.publishedHuddle = publishingHuddle
                            }
                            self.inflightSnapshots = max(self.inflightSnapshots - 1, 0)
                        }
                    }
                }
            } else {
                // A non-finite number cannot be stored; the next publication sends the whole state again.
                snapshotBaseline = [:]
            }
            if let result = e.result, !resultBusy {
                resultBusy = true
                let value = AmuduCodec.outcome(result)
                r.child("results/final").runTransactionBlock({ d in
                    if let current = d.value, !(current is NSNull) { return TransactionResult.abort() }
                    d.value = value
                    return TransactionResult.success(withValue: d)
                }, andCompletionBlock: { [weak self] error, _, _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let error {
                            self.resultBusy = false
                            self.fail(error)
                        } else {
                            self.recordResult(e, r)
                        }
                    }
                })
            }
        }
        manageHuddle(e)
    }

    /// After `results/final`: a league round is recorded in the league before the room is marked finished.
    private func recordResult(_ e: AmuduEngine, _ r: DatabaseReference) {
        let league = meta.str("league")
        guard !Kotlin.isBlank(league), let database = db else {
            r.child("meta/phase").setValue("finished")
            return
        }
        FamilyLeague.record(database, league, e, error: { [weak self] error in
            self?.resultBusy = false
            self?.fail(error)
        }, done: {
            r.child("meta/phase").setValue("finished")
            database.reference(withPath: "minikAmudu/leagues/\(league)/activeRoom").removeValue()
        })
    }

    private func claim() {
        guard let r = room else { return }
        claiming = true
        let me = uid
        let stamp = now()
        r.child("meta").runTransactionBlock({ d in
            let lease = (d.childData(byAppendingPath: "leaseUntil").value as? NSNumber)?.int64Value ?? Int64.max
            if lease >= stamp || (d.childData(byAppendingPath: "phase").value as? String) != "playing" { return TransactionResult.abort() }
            d.childData(byAppendingPath: "host").value = me
            let epoch = (d.childData(byAppendingPath: "epoch").value as? NSNumber)?.int64Value ?? 0
            d.childData(byAppendingPath: "epoch").value = epoch + 1
            d.childData(byAppendingPath: "leaseUntil").value = stamp + 8000
            return TransactionResult.success(withValue: d)
        }, andCompletionBlock: { [weak self] error, _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.claiming = false
                if let error { self.fail(error) }
            }
        })
    }

    private func connectedHumanLeader(_ e: AmuduEngine, excluding target: String) -> String? {
        let keys = members.filter { entry in
            let n = node(entry.value)
            return entry.key != target && e.actor(entry.key)?.active == true && !n.flag("bot") && n.flag("connected")
        }.map { $0.key }
        return keys.min(by: Kotlin.less)
    }

    private func manageHuddle(_ e: AmuduEngine) {
        if e.phase != .huddle { return }
        guard let r = room else { return }
        let id = "h\(e.huddleSerial)"
        if id != huddleId {
            huddleId = id
            huddleMeta = [:]
            huddleResult = [:]
            huddleSuggestions = [:]
            huddleVotes = [:]
            huddleWriting = false
            huddleCommitted = false
            watch("huddles/\(id)/meta") { [weak self] n in
                guard let self else { return }
                let first = self.huddleMeta.isEmpty
                self.huddleMeta = n
                if first && !n.isEmpty && self.uid != n.str("target") {
                    self.watch("huddles/\(id)/suggestions") { [weak self] s in self?.huddleSuggestions = AmuduCodec.stringMap(s) }
                    self.watch("huddles/\(id)/votes") { [weak self] s in self?.huddleVotes = AmuduCodec.stringMap(s) }
                }
            }
            watch("huddles/\(id)/result") { [weak self] n in
                guard let self else { return }
                self.huddleResult = n
                if !n.isEmpty && !self.huddleWriting { self.huddleCommitted = true }
            }
        }
        // Rules intentionally require the public phase to be committed first. A local
        // optimistic snapshot is insufficient; wait for the completed publication.
        if authority && huddleMeta.isEmpty && publishedHuddle == e.huddleSerial && !creatingHuddle && now() >= nextHuddleAttempt {
            let leader = connectedHumanLeader(e, excluding: e.huddleTarget)
            creatingHuddle = true
            var value: Node = [:]
            value["target"] = e.huddleTarget
            value["leader"] = leader ?? uid
            value["deadline"] = now() + Kotlin.toLong(e.config.huddleSeconds * 1000)
            value["botOnly"] = leader == nil
            r.child("huddles/\(id)/meta").setValue(value) { [weak self] error, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.creatingHuddle = false
                    self.nextHuddleAttempt = self.now() + 1000
                    if let error {
                        self.huddleMeta = [:]
                        self.fail(error)
                    }
                }
            }
        }
        if authority && !huddleResult.isEmpty && (huddleMeta.str("leader") != uid || huddleCommitted) {
            _ = e.applyHuddle(huddleResult.str("name"))
            return
        }
        if authority && !huddleMeta.isEmpty && !replacingLeader {
            let current = huddleMeta.str("leader")
            if !node(members[current]).flag("connected") {
                let replacement = connectedHumanLeader(e, excluding: e.huddleTarget)
                replacingLeader = true
                let change: [AnyHashable: Any] = ["leader": replacement ?? uid, "botOnly": replacement == nil]
                r.child("huddles/\(id)/meta").updateChildValues(change) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.replacingLeader = false }
                }
            }
        }
        if huddleMeta.isEmpty || huddleMeta.str("leader") != uid || huddleWriting { return }
        let target = huddleMeta.str("target")
        if huddleMeta.flag("botOnly") {
            if Double(now()) > huddleMeta.num("deadline") {
                huddleWriting = true
                writeHuddleResult(r, id, name: Words.suggestion(e.huddleSerial, hebrew: identity.hebrew), winner: "house")
            }
            return
        }
        let bots = members.filter { $0.key != target && e.actor($0.key)?.active == true && node($0.value).flag("bot") }
        let botIds = bots.keys.sorted(by: Kotlin.less)
        var used = Array(huddleSuggestions.values)
        for bid in botIds where huddleSuggestions[bid] == nil {
            let word = Words.uniqueSuggestion(Int(Kotlin.hashCode(bid)), hebrew: node(bots[bid]).flag("hebrew"), used: used)
            if !Kotlin.isBlank(word) {
                used.append(word)
                r.child("huddles/\(id)/suggestions/\(bid)").setValue(word)
            }
        }
        if !huddleSuggestions.isEmpty {
            let keys = huddleSuggestions.keys.sorted(by: Kotlin.less)
            for bid in botIds where huddleVotes[bid] == nil {
                r.child("huddles/\(id)/votes/\(bid)").setValue(keys[Kotlin.floorMod(Int(Kotlin.hashCode(bid)), keys.count)])
            }
        }
        let eligible = members.keys.filter { $0 != target && e.actor($0)?.active == true }
        let deadline = huddleMeta.num("deadline")
        let early = Double(now()) >= deadline - e.config.huddleSeconds * 1000 + 2000 && eligible.allSatisfy { huddleVotes[$0] != nil }
        if Double(now()) >= deadline || early {
            let fallback = Words.suggestion(e.huddleSerial, hebrew: identity.hebrew)
            let humans = members.filter { e.actor($0.key)?.active == true && !node($0.value).flag("bot") }.map { $0.key }
            let eligibleProposals = huddleSuggestions.filter { $0.key.hasPrefix("word_") || (e.actor($0.key)?.active == true && $0.key != target) }
            let eligibleVotes = huddleVotes.filter { e.actor($0.key)?.active == true && $0.key != target }
            // Kotlin `human?.takeIf{it != target}?.let{eligibleVotes[it]}?.takeIf{it in eligibleProposals}`.
            var priority: String?
            if humans.count == 1, humans[0] != target, let choice = eligibleVotes[humans[0]], eligibleProposals[choice] != nil {
                priority = choice
            }
            let winner = priority ?? AmuduEngine.rankedWinner(keys: Array(eligibleProposals.keys), votes: Array(eligibleVotes.values))
            huddleWriting = true
            let name = winner.flatMap { huddleSuggestions[$0] } ?? fallback
            writeHuddleResult(r, id, name: name, winner: winner ?? "fallback")
        }
    }

    private func writeHuddleResult(_ r: DatabaseReference, _ id: String, name: String, winner: String) {
        let value: [String: Any] = ["name": name, "winner": winner, "at": ServerValue.timestamp()]
        r.child("huddles/\(id)/result").setValue(value) { [weak self] error, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.huddleWriting = false
                    self.huddleCommitted = false
                    self.huddleResult = [:]
                    self.fail(error)
                } else {
                    self.huddleCommitted = true
                }
            }
        }
    }

    func huddleRemainingSeconds() -> Int {
        if !huddleMeta.isEmpty {
            return max(Kotlin.toInt(ceil((huddleMeta.num("deadline") - Double(now())) / 1000.0)), 0)
        }
        let deadline = world?.huddleDeadline ?? 0.0
        let time = world?.time ?? 0.0
        return max(Kotlin.toInt(ceil(deadline - time)), 0)
    }

    /// Android `propose`: one person may offer several distinct words; a deterministic, normalized key prevents two
    /// people submitting the same word concurrently, and the proposer votes for it.
    func propose(_ text: String) {
        if world?.actor(uid)?.active != true || Kotlin.isBlank(huddleId) || !Words.validSuggestion(text) || huddleMeta.str("target") == uid { return }
        guard let r = room else { return }
        let word = Words.nfkcTrim(text)
        if huddleSuggestions.values.contains(where: { Words.normalize($0) == Words.normalize(word) }) { return }
        let h = huddleId
        let key = "word_" + Words.proposalKey(word)
        let me = uid
        r.child("huddles/\(h)/suggestions/\(key)").runTransactionBlock({ d in
            if let current = d.value, !(current is NSNull) { return TransactionResult.abort() }
            d.value = word
            return TransactionResult.success(withValue: d)
        }, andCompletionBlock: { [weak self] error, committed, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.fail(error, "nickname")
                    return
                }
                if committed && h == self.huddleId {
                    r.child("huddles/\(h)/votes/\(me)").setValue(key) { [weak self] failure, _ in
                        MainActor.assumeIsolated {
                            if let failure { self?.fail(failure, "nickname vote") }
                        }
                    }
                }
            }
        })
    }

    func vote(_ id: String) {
        if world?.actor(uid)?.active != true || huddleSuggestions[id] == nil || huddleMeta.str("target") == uid { return }
        guard let r = room else { return }
        r.child("huddles/\(huddleId)/votes/\(uid)").setValue(id) { [weak self] error, _ in
            MainActor.assumeIsolated {
                if let error { self?.fail(error) }
            }
        }
    }

    /// Android `setPaused`: only the last active human pauses the shared match (Command.Pause).
    func setPaused(_ value: Bool) {
        guard let e = world else { return }
        if e.activeHumans > 1 || e.actor(uid)?.active != true { return }
        if authority {
            if e.command(uid, UUID().uuidString.lowercased(), .pause(value: value)), let r = room {
                snapshotBaseline = [:]
                motionPublication.reset()
                let update: [AnyHashable: Any] = ["public": AmuduCodec.shared(e), "checkpoint": AmuduCodec.checkpoint(e)]
                if JSONSerialization.isValidJSONObject(update) { r.updateChildValues(update) }
            }
        } else {
            if let index = pending.firstIndex(where: { $0.0 == "pause" }) {
                pending[index] = ("pause", .pause(value: value))
            } else {
                pending.append(("pause", .pause(value: value)))
            }
            flush()
        }
    }

    func background() {
        setPaused(true)
        if !deleting, let r = room, !uid.isEmpty {
            if meta.str("phase") == "playing" && world?.result == nil {
                pending.removeAll { $0.0 == "move" }
                pending.append(("move", .move(V.zero)))
                flush()
            }
            world?.actor(uid)?.move = V.zero
            r.child("members/\(uid)/connected").setValue(false)
            if authority && meta.str("phase") == "playing" { r.child("meta/leaseUntil").setValue(0) }
        }
        active = false
        pending.removeAll()
    }

    func foreground() {
        if closed { return }
        active = true
        setPaused(false)
        if room != nil && !uid.isEmpty { registerPresence() }
    }

    /// Android `close(leave = true)`: leaving a lobby removes this player (the host's lobby removes the room); leaving
    /// a started game marks the player as departed. `leave = false` only stops listening.
    func close(leave: Bool = true) {
        if closed { return }
        if leave, let r = room, !uid.isEmpty {
            if meta.str("phase") == "lobby" && authority {
                deleting = true
                r.removeValue()
                model?.forgetRoom(code)
            } else if meta.str("phase") == "lobby" {
                deleting = true
                let slot = node(members[uid]).str("slot")
                if !Kotlin.isBlank(slot) { r.updateChildValues(["members/" + uid: NSNull(), "slots/" + slot: NSNull()]) }
                model?.forgetRoom(code)
            } else {
                r.child("members/" + uid).updateChildValues(["connected": false, "left": true]) { [weak self] error, _ in
                    MainActor.assumeIsolated {
                        if error == nil { self?.cleanupIfUnused() }
                    }
                }
                model?.forgetRoom(code)
            }
        }
        if leave { background() }
        closed = true
        pump?.invalidate()
        pump = nil
        openTimeout?.cancel()
        stopCommands()
        for (ref, handle) in listeners { ref.removeObserver(withHandle: handle) }
        listeners.removeAll()
        view?.sendCommand = nil
        view?.remoteUpdate = nil
    }

    /// Android `resultsVisible`: this player has seen the results; the room may be removed once everyone has.
    func resultsVisible() {
        if seenResult { return }
        guard let r = room else { return }
        seenResult = true
        r.child("members/\(uid)/resultsSeen").setValue(true) { [weak self] error, _ in
            MainActor.assumeIsolated {
                if error == nil { self?.maintainCleanup() }
            }
        }
        model?.forgetRoom(code)
    }

    func hasShownResult() -> Bool { return seenResult }

    func leaveLobby(_ done: () -> Void) {
        close()
        done()
    }

    private func maintainCleanup() {
        guard !closed, !deleting, let r = room, !members.isEmpty else { return }
        let humans = members.filter { !node($0.value).flag("bot") }
        let alone = !humans.contains { $0.key != uid && node($0.value).flag("connected") }
        if alone && meta.str("phase") == "lobby" && !disconnectDelete {
            disconnectDelete = true
            r.onDisconnectRemoveValue { [weak self] error, _ in
                MainActor.assumeIsolated {
                    if error != nil { self?.disconnectDelete = false }
                }
            }
        } else if (!alone || meta.str("phase") != "lobby") && disconnectDelete {
            disconnectDelete = false
            // Cancelling a parent disconnect operation also cancels its child registrations.
            let me = uid
            r.cancelDisconnectOperations { [weak self] error, _ in
                MainActor.assumeIsolated {
                    guard let self, error == nil, !self.closed else { return }
                    r.child("members/\(me)/connected").onDisconnectSetValue(false)
                }
            }
        }
        if meta.str("phase") == "finished" && humans.allSatisfy({ !node($0.value).flag("connected") || node($0.value).flag("resultsSeen") }) {
            cleanupIfUnused()
        }
    }

    private func cleanupIfUnused() {
        guard let r = room else { return }
        Task { @MainActor [weak self] in
            guard let snapshot = try? await r.child("members").getData(), let self else { return }
            self.removeIfUnused(r, self.node(snapshot.value))
        }
    }

    /// Removal rules recheck current connections; a concurrent reconnect wins.
    private func removeIfUnused(_ r: DatabaseReference, _ current: Node) {
        let humans = current.values.map { node($0) }.filter { !$0.flag("bot") }
        let finished = meta.str("phase") == "finished"
        if humans.contains(where: { $0.flag("connected") && (!finished || !$0.flag("resultsSeen")) }) { return }
        let roomCode = code
        r.removeValue { [weak self] error, _ in
            MainActor.assumeIsolated {
                if error == nil { self?.model?.forgetRoom(roomCode) }
            }
        }
    }

    private func fail(_ error: Error, _ operation: String = "connection") {
        LagDiagnostics.error(operation)
        if !closed { status(OnlineErrors.message(error)) }
        let tag = "SpudOnline"
        NSLog("%@ %@: %@", tag, operation, String(describing: type(of: error)))
    }
}

#else

/// Builds without the Firebase packages keep the same API and stay offline.
@MainActor final class OnlineRoom {
    private(set) var huddleSuggestions: [String: String] = [:]
    private(set) var huddleVotes: [String: String] = [:]
    var onOpenFailed: (@MainActor (String) -> Void)?

    init(model: AppModel, identity: Member, config: GameConfig, house: [String], leagueId: String = "", fixedCode: String = "") {}

    func open(join: String?, onStatus: @escaping @MainActor (String) -> Void) {
        let text = GameText.t("Online activation is pending.", "הפעלת האונליין עדיין בהמתנה.", hebrew: AppText.language == "he")
        if let failed = onOpenFailed { failed(text) } else { onStatus(text) }
    }

    func attach(_ v: ArenaView) {}
    func startWithoutUnready() {}
    func canFinishGame() -> Bool { return false }
    func endGame() {}
    func setPaused(_ value: Bool) {}
    func huddleRemainingSeconds() -> Int { return 0 }
    func propose(_ text: String) {}
    func vote(_ id: String) {}
    func background() {}
    func foreground() {}
    func close(leave: Bool = true) {}
    func resultsVisible() {}
    func hasShownResult() -> Bool { return false }
    func leaveLobby(_ done: () -> Void) { done() }
}

#endif
