import Foundation

#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseDatabase)
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase

/// Android `OnlineRoom`: private Realtime Database rooms under `minikAmudu/rooms/{CODE}`.
/// Paths, field names, enum names, transactions, leases and huddle rules are identical to Android, so iOS and
/// Android phones share rooms. Firebase is used only when this app's GoogleService-Info.plist is bundled.
@MainActor final class OnlineRoom {
    static let appName = "minik-amudu-production"
    static let root = "minikAmudu/rooms/"

    private struct Connection {
        let auth: Auth
        let database: Database
    }

    private static var connections: [String: Connection] = [:]

    /// The named Firebase app, created only from a bundled plist for this bundle ID with a database URL.
    private static func connection() -> Connection? {
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
    private weak var model: AppModel?
    private let identity: Member
    private let cfg: GameConfig
    private let house: [String]
    private var auth: Auth?
    private var db: Database?
    private var room: DatabaseReference?
    private var code = ""
    private var meta: Node = [:]
    private var members: Node = [:]
    private var world: AmuduEngine?
    private weak var view: ArenaView?
    private var closed = false
    private var active = true
    /// Android `connected`: the Realtime Database `.info/connected` state.
    private var isConnected = false
    private var authority = false
    private var claiming = false
    private var loading = false
    private var starting = false
    private var publishing = false
    private var resultBusy = false
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
    private var previousPositions: [String: V] = [:]
    private var previousBall = V.zero
    private var previousHeight = 0.0
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
    private var publishedHuddle = 0
    private var creatingHuddle = false
    private var nextHuddleAttempt: Int64 = 0
    private var pump: Timer?
    private var clockOpened = false

    init(model: AppModel, identity: Member, config: GameConfig, house: [String]) {
        self.model = model
        self.identity = identity
        self.cfg = config
        self.house = house
    }

    private func now() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000) + serverOffset
    }

    private func tr(_ en: String, _ he: String) -> String {
        return GameText.t(en, he, hebrew: AppText.language == "he")
    }

    private func node(_ value: Any?) -> Node { return AmuduCodec.node(value) }

    private func slotNumber(_ n: Node) -> Int { return Int(n.str("slot")) ?? 0 }

    func open(join: String?, onStatus: @escaping @MainActor (String) -> Void) {
        status = onStatus
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
                self.isConnected = (snapshot.value as? Bool) == true
                self.view?.networkWaiting = !self.isConnected
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
                self.status(error.localizedDescription)
            }
        })
        listeners.append((clockRef, handle))
    }

    private func create() {
        guard let database = db else { return }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var made = ""
        for _ in 0..<6 { made.append(alphabet[Int.random(in: 0..<alphabet.count)]) }
        code = made
        let r = database.reference(withPath: OnlineRoom.root + code)
        room = r
        let stamp = now()
        var roster: [(String, Node)] = []
        var hostNode = AmuduCodec.member(identity.copy(id: uid))
        hostNode["slot"] = "0"
        roster.append((uid, hostNode))
        let bots = Array(AmuduCharacters.availableBots(humans: [identity], requested: house).prefix(max(cfg.participants - 1, 0)))
        for (i, id) in bots.enumerated() {
            let c = AmuduCharacters.get(id)
            let m = Member("house\(i)", id, c.name(hebrew: identity.hebrew), bot: true, hebrew: identity.hebrew)
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
        metaNode["config"] = AmuduCodec.config(cfg)
        let initial: Node = ["meta": metaNode, "members": memberNodes, "slots": slots]
        Task { @MainActor [weak self] in
            do {
                _ = try await r.setValue(initial)
                self?.listen()
            } catch {
                self?.fail(error)
            }
        }
    }

    private func enter(_ value: String) {
        guard let database = db else { return }
        code = value
        let r = database.reference(withPath: OnlineRoom.root + code)
        room = r
        let me = uid
        Task { @MainActor [weak self] in
            do {
                let snapshot = try await r.child("meta").getData()
                guard let self else { return }
                if !snapshot.exists() {
                    self.status(self.tr("Room not found.", "החדר לא נמצא."))
                    return
                }
                self.meta = self.node(snapshot.value)
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
        guard let r = room else { return }
        if Double(index) >= node(meta["config"]).num("participants", 6.0) {
            status(tr("This room is full.", "החדר מלא."))
            return
        }
        let me = uid
        r.child("slots/\(index)").runTransactionBlock({ data in
            if let current = data.value, !(current is NSNull), (current as? String) != me {
                return TransactionResult.abort()
            }
            data.value = me
            return TransactionResult.success(withValue: data)
        }, andCompletionBlock: { [weak self] error, committed, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.status(error.localizedDescription)
                    return
                }
                if !committed {
                    self.claimSlot(index + 1)
                    return
                }
                var n = AmuduCodec.member(self.identity.copy(id: me))
                n["slot"] = String(index)
                Task { @MainActor [weak self] in
                    do {
                        _ = try await r.child("members/" + me).setValue(n)
                        self?.listen()
                    } catch {
                        self?.fail(error)
                    }
                }
            }
        })
    }

    private func listen() {
        guard !closed, let r = room else { return }
        let presence = r.child("members/\(uid)/connected")
        presence.onDisconnectSetValue(false)
        presence.setValue(true)
        watch("meta") { [weak self] n in
            guard let self else { return }
            self.meta = n
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
                self.received = uptimeMs()
                self.version += 1
                self.maybeWorld()
            }
        }
        startPump()
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
        oldMembers = n
        members = n
        if authority && !starting && !reconciling && meta.str("phase") == "lobby" {
            let humanArt = n.values.filter { !node($0).flag("bot") }.map { node($0).str("character") }
            let botArt = n.values.filter { node($0).flag("bot") }.map { node($0).str("character") }
            if botArt.contains(where: { humanArt.contains($0) }) || Set(botArt).count != botArt.count {
                reconcileBots(fillAlone: false) {}
            }
        }
        lobby()
        maybeWorld()
        if authority, let w = world {
            for a in w.actors where !a.member.bot && !node(members[a.member.id]).flag("connected") { a.move = V.zero }
        }
    }

    private func watch(_ path: String, _ block: @escaping @MainActor (Node) -> Void) {
        guard let r = room else { return }
        let ref = r.child(path)
        let handle = ref.observe(.value, with: { [weak self] snapshot in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                block(self.node(snapshot.value))
            }
        }, withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                self.status(error.localizedDescription)
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

    private func start() {
        if !authority || starting || meta.str("phase") != "lobby" { return }
        if reconciling {
            status(tr("Updating the house players. Tap Start in a moment.", "מעדכנים את שחקני הבית. לחצו התחלה בעוד רגע."))
            return
        }
        if members.contains(where: { $0.key != uid && !node($0.value).flag("ready") }) {
            status(tr("Everyone must be Ready.", "כולם צריכים להיות מוכנים."))
            return
        }
        starting = true
        reconcileBots(fillAlone: true) { [weak self] in
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
                    if let error { self.status(error.localizedDescription) }
                }
            })
        }
    }

    private func reconcileBots(fillAlone: Bool, done: @escaping @MainActor () -> Void) {
        guard let r = room else { return }
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
        Task { @MainActor [weak self] in
            do {
                _ = try await r.updateChildValues(update)
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
                        engine = try AmuduEngine(members: roster, config: config, seed: Kotlin.toLong(self.meta.num("seed")), id: self.code)
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
        } else if !latest.isEmpty {
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
                self.world?.command(self.uid, UUID().uuidString.lowercased(), cmd)
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
        }
        v.remoteUpdate = { [weak self, weak v] in
            guard let self, let v else { return }
            self.remoteUpdate(v)
        }
    }

    /// Guests apply each 12 Hz snapshot once, then interpolate positions over 100 ms.
    private func remoteUpdate(_ v: ArenaView) {
        if !SnapshotGuard.playable(latest) { return }
        if version != applied {
            previousPositions.removeAll()
            for a in v.engine.actors { previousPositions[a.member.id] = a.position }
            previousBall = v.engine.ball.position
            previousHeight = v.engine.ball.height
            AmuduCodec.apply(v.engine, latest)
            applied = version
        }
        let t = Kotlin.clamp(Double(uptimeMs() - received) / 100.0, 0.0, 1.0)
        for (id, value) in node(latest["actors"]) {
            guard let a = v.engine.actor(id) else { continue }
            let target = AmuduCodec.vector(node(value)["position"])
            let from = previousPositions[id] ?? target
            a.position = from + (target - from) * t
        }
        let ball = node(latest["ball"])
        let ballTarget = AmuduCodec.vector(ball["position"])
        v.engine.ball.position = previousBall + (ballTarget - previousBall) * t
        v.engine.ball.height = previousHeight + (ball.num("height") - previousHeight) * t
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
                self.status(error.localizedDescription)
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
                    self.world?.command(id, snapshot.key, cmd)
                }
                snapshot.ref.removeValue()
            }
        }, withCancel: { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, self.authority, !self.closed else { return }
                self.status(error.localizedDescription)
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
        var update: [AnyHashable: Any] = [:]
        for (_, cmd) in pending {
            var n = AmuduCodec.command(cmd)
            n["at"] = ServerValue.timestamp()
            update[UUID().uuidString.lowercased()] = n
        }
        pending.removeAll()
        let path = "commands/" + uid
        Task { @MainActor [weak self] in
            do {
                _ = try await r.child(path).updateChildValues(update)
            } catch {
                self?.fail(error)
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
            return
        }
        let stamp = now()
        view?.networkWaiting = !authority && (received == 0 || uptimeMs() - received > 4500)
        if authority && stamp - lastHeartbeat > 2000 {
            lastHeartbeat = stamp
            r.child("meta/leaseUntil").setValue(stamp + 8000)
        }
        if !authority && meta.num("leaseUntil") < Double(stamp) && !claiming { claim() }
        flush()
        guard let e = world else { return }
        if authority && !publishing && stamp - lastPublish > Int64(1000 / e.config.snapshotHz) {
            publishing = true
            lastPublish = stamp
            let publishingHuddle = e.phase == .huddle ? e.huddleSerial : 0
            let snapshot: [AnyHashable: Any] = ["public": AmuduCodec.shared(e), "checkpoint": AmuduCodec.checkpoint(e)]
            if JSONSerialization.isValidJSONObject(snapshot) {
                Task { @MainActor [weak self] in
                    do {
                        _ = try await r.updateChildValues(snapshot)
                        self?.publishedHuddle = publishingHuddle
                    } catch {
                        // Android ignores a failed publication; the next one follows 83 ms later.
                    }
                    self?.publishing = false
                }
            } else {
                publishing = false
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
                            self.status(error.localizedDescription)
                        } else {
                            r.child("meta/phase").setValue("finished")
                        }
                    }
                })
            }
        }
        manageHuddle(e)
    }

    private func claim() {
        guard let r = room else { return }
        claiming = true
        let me = uid
        let stamp = now()
        r.child("meta").runTransactionBlock({ d in
            let lease = (d.childData(byAppendingPath: "leaseUntil").value as? NSNumber)?.int64Value ?? Int64.max
            if lease >= stamp { return TransactionResult.abort() }
            d.childData(byAppendingPath: "host").value = me
            let epoch = (d.childData(byAppendingPath: "epoch").value as? NSNumber)?.int64Value ?? 0
            d.childData(byAppendingPath: "epoch").value = epoch + 1
            d.childData(byAppendingPath: "leaseUntil").value = stamp + 8000
            return TransactionResult.success(withValue: d)
        }, andCompletionBlock: { [weak self] error, _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.claiming = false
                if let error { self.status(error.localizedDescription) }
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
            Task { @MainActor [weak self] in
                do {
                    _ = try await r.child("huddles/\(id)/meta").setValue(value)
                } catch {
                    self?.huddleMeta = [:]
                    self?.fail(error)
                }
                guard let self else { return }
                self.creatingHuddle = false
                self.nextHuddleAttempt = self.now() + 1000
            }
        }
        if authority && !huddleResult.isEmpty && (huddleMeta.str("leader") != uid || huddleCommitted) {
            e.applyHuddle(huddleResult.str("name"))
            return
        }
        if authority && !huddleMeta.isEmpty && !replacingLeader {
            let current = huddleMeta.str("leader")
            if !node(members[current]).flag("connected") {
                let replacement = connectedHumanLeader(e, excluding: e.huddleTarget)
                replacingLeader = true
                let change: [AnyHashable: Any] = ["leader": replacement ?? uid, "botOnly": replacement == nil]
                Task { @MainActor [weak self] in
                    _ = try? await r.child("huddles/\(id)/meta").updateChildValues(change)
                    self?.replacingLeader = false
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
        for (bid, b) in bots where huddleSuggestions[bid] == nil {
            r.child("huddles/\(id)/suggestions/\(bid)").setValue(Words.suggestion(Int(Kotlin.hashCode(bid)), hebrew: node(b).flag("hebrew")))
        }
        if !huddleSuggestions.isEmpty {
            let keys = huddleSuggestions.keys.sorted(by: Kotlin.less)
            for (bid, _) in bots where huddleVotes[bid] == nil {
                r.child("huddles/\(id)/votes/\(bid)").setValue(keys[Kotlin.floorMod(Int(Kotlin.hashCode(bid)), keys.count)])
            }
        }
        if Double(now()) >= huddleMeta.num("deadline") {
            let fallback = Words.suggestion(e.huddleSerial, hebrew: identity.hebrew)
            let humans = members.filter { e.actor($0.key)?.active == true && !node($0.value).flag("bot") }.map { $0.key }
            let eligibleProposals = huddleSuggestions.filter { e.actor($0.key)?.active == true && $0.key != target }
            let eligibleVotes = huddleVotes.filter { e.actor($0.key)?.active == true && $0.key != target }
            var priority: String?
            if humans.count == 1 {
                let human = humans[0]
                if human != target && eligibleProposals[human] != nil { priority = human }
            }
            let winner = priority ?? AmuduEngine.rankedWinner(keys: Array(eligibleProposals.keys), votes: Array(eligibleVotes.values))
            huddleWriting = true
            let name = winner.flatMap { huddleSuggestions[$0] } ?? fallback
            writeHuddleResult(r, id, name: name, winner: winner ?? "fallback")
        }
    }

    private func writeHuddleResult(_ r: DatabaseReference, _ id: String, name: String, winner: String) {
        let value: [String: Any] = ["name": name, "winner": winner, "at": ServerValue.timestamp()]
        Task { @MainActor [weak self] in
            do {
                _ = try await r.child("huddles/\(id)/result").setValue(value)
                self?.huddleCommitted = true
            } catch {
                guard let self else { return }
                self.huddleWriting = false
                self.huddleCommitted = false
                self.huddleResult = [:]
                self.fail(error)
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

    func propose(_ text: String) {
        if world?.actor(uid)?.active != true || Kotlin.isBlank(huddleId) || !Words.validSuggestion(text) || huddleMeta.str("target") == uid { return }
        guard let r = room else { return }
        let value = Words.nfkcTrim(text)
        let path = "huddles/\(huddleId)/suggestions/\(uid)"
        Task { @MainActor [weak self] in
            do {
                _ = try await r.child(path).setValue(value)
            } catch {
                self?.fail(error)
            }
        }
    }

    func vote(_ id: String) {
        if world?.actor(uid)?.active != true || huddleSuggestions[id] == nil || huddleMeta.str("target") == uid { return }
        guard let r = room else { return }
        let path = "huddles/\(huddleId)/votes/\(uid)"
        Task { @MainActor [weak self] in
            do {
                _ = try await r.child(path).setValue(id)
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Android `setPaused`: only the last active human pauses the shared match (Command.Pause).
    func setPaused(_ value: Bool) {
        guard let e = world else { return }
        if e.activeHumans > 1 || e.actor(uid)?.active != true { return }
        if authority {
            if e.command(uid, UUID().uuidString.lowercased(), .pause(value: value)), let r = room {
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
        if let r = room, !uid.isEmpty {
            if meta.str("phase") == "playing" && world?.result == nil {
                pending.removeAll { $0.0 == "move" }
                pending.append(("move", .move(V.zero)))
                flush()
            }
            world?.actor(uid)?.move = V.zero
            r.child("members/\(uid)/connected").setValue(false)
            if authority { r.child("meta/leaseUntil").setValue(0) }
        }
        active = false
        pending.removeAll()
    }

    func foreground() {
        if closed { return }
        active = true
        setPaused(false)
        if let r = room, !uid.isEmpty { r.child("members/\(uid)/connected").setValue(true) }
    }

    func close() {
        if closed { return }
        background()
        closed = true
        pump?.invalidate()
        pump = nil
        stopCommands()
        for (ref, handle) in listeners { ref.removeObserver(withHandle: handle) }
        listeners.removeAll()
        view?.sendCommand = nil
        view?.remoteUpdate = nil
    }

    private func fail(_ error: Error?) {
        if closed { return }
        if let error {
            status(error.localizedDescription)
        } else {
            status(tr("Connection failed.", "החיבור נכשל."))
        }
    }
}

#else

/// Builds without the Firebase packages keep the same API and stay offline.
@MainActor final class OnlineRoom {
    private(set) var huddleSuggestions: [String: String] = [:]
    private(set) var huddleVotes: [String: String] = [:]

    init(model: AppModel, identity: Member, config: GameConfig, house: [String]) {}

    func open(join: String?, onStatus: @escaping @MainActor (String) -> Void) {
        onStatus(GameText.t("Online activation is pending.", "הפעלת האונליין עדיין בהמתנה.", hebrew: AppText.language == "he"))
    }

    func attach(_ v: ArenaView) {}
    func endGame() {}
    func setPaused(_ value: Bool) {}
    func huddleRemainingSeconds() -> Int { return 0 }
    func propose(_ text: String) {}
    func vote(_ id: String) {}
    func background() {}
    func foreground() {}
    func close() {}
}

#endif
