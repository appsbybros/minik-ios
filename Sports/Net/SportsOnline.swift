import Foundation

/// What the room needs from the app (Android `SportsActivity` callbacks).
@MainActor
protocol SportsOnlineHost: AnyObject {
    var hebrew: Bool { get }
    func receptionSlow() -> Bool
    func onlineError(_ text: String)
    func sound(_ name: String)
    func lobby(_ code: String, _ members: [Participant], _ ready: Set<String>, _ host: Bool, _ link: SportsOnline)
    func present(_ e: SportsEngine, _ id: String, _ link: SportsOnline?)
    func refreshOnlineResult()
    func publicTournaments(_ entries: [(String, Int, String)])
}

/// Port of Android SportsOnline.kt: the Realtime Database room authority and own-input channels
/// under `minikSquash/` or `minikBeachVolley/` (meta, slots, members, world, commands, results and
/// the public tournament directory). Field names, transactions, the 50 ms pump, 10 s leases and
/// the authority handover match Android, so iOS and Android players share rooms. It never writes to
/// another Minik game's root.
@MainActor
final class SportsOnline {
    private(set) var uid = ""
    private(set) var authority = false
    weak var view: SportsView?
    private weak var host: SportsOnlineHost?
    private var config: SportsConfig
    private let avatar: String
    private let points: Int
    private let rounds: Int
    private let publicCup: Bool

    var round: Int { return NodeValue.number(meta["round"]).map { KotlinNumber.int($0) } ?? 1 }
    var totalRounds: Int { return NodeValue.number(meta["rounds"]).map { KotlinNumber.int($0) } ?? 1 }
    private(set) var results: [String: Node] = [:]

    func cupWins(_ team: Int) -> Int {
        let recorded = results.values.filter { NodeValue.number($0["winner"]).map { KotlinNumber.int($0) } == team }.count
        guard let w = world else { return recorded }
        let pending = w.phase == .finished && w.winner == team && results[w.matchId] == nil
        return recorded + (pending ? 1 : 0)
    }

    var roomCode: String { return code }
    private var database: SportsDatabase?
    private var root = ""
    private var roomPath = ""
    private var directoryPath = ""
    private var roomReady = false
    private var code = ""
    private var closed = false
    private var foreground = true
    private var phase = "lobby"
    private var meta: Node = [:]
    /// Android `LinkedHashMap(n.mapValues { ... })`: the members in Java HashMap order.
    private var memberOrder: [String] = []
    private var members: [String: Node] = [:]
    private var world: SportsEngine?
    private var latest: Node?
    private var tick = 0
    private var writing = false
    private var starting = false
    private var commandSeq: Int64 = 0
    private let prefix = UUID().uuidString.lowercased()
    /// Android `LinkedHashSet` of applied command keys.
    private var acceptedOrder: [String] = []
    private var acceptedSet = Set<String>()
    /// Android `LinkedHashMap` of own commands not yet acknowledged.
    private var pendingOrder: [String] = []
    private var watchers: [Int] = []
    private var commandsToken: Int?
    private var signature = ""
    private var role = ""
    private var claiming = false
    private var finishing = false
    private var publicToken: Int?
    private var pumpTask: Task<Void, Never>?

    init(host: SportsOnlineHost, config: SportsConfig, avatar: String, points: Int, rounds: Int = 1, publicCup: Bool = false) {
        self.host = host
        self.config = config
        self.avatar = avatar
        self.points = points
        self.rounds = rounds
        self.publicCup = publicCup
    }

    private func tr(_ en: String, _ he: String) -> String { return SportsText.t(en, he, host?.hebrew ?? false) }

    private func path(_ child: String) -> String { return roomPath + "/" + child }

    private func error(_ text: String) { host?.onlineError(text) }

    // MARK: Accepted commands

    private func accept(_ key: String) {
        if acceptedSet.insert(key).inserted { acceptedOrder.append(key) }
    }

    private func clearAccepted() {
        acceptedOrder.removeAll()
        acceptedSet.removeAll()
    }

    // MARK: Opening

    func open(_ join: String?) {
        let emulated = SportsLaunch.qaOnline
        if !emulated && !SportsDatabaseFactory.productionAvailable {
            error(tr("Online play needs this app's Firebase registration. Local games and cups are ready to play.",
                     "משחק ברשת דורש רישום Firebase של האפליקציה. אפשר לשחק במשחקים ובגביעים מקומיים."))
            return
        }
        let db: SportsDatabase
        do {
            db = try SportsDatabaseFactory.make(host: "127.0.0.1", emulator: emulated)
        } catch {
            self.error(tr("Online play needs this app's Firebase registration. Local games and cups are ready to play.",
                          "משחק ברשת דורש רישום Firebase של האפליקציה. אפשר לשחק במשחקים ובגביעים מקומיים."))
            return
        }
        database = db
        db.signIn { [weak self] result in
            guard let self = self, !self.closed else { return }
            switch result {
            case .success(let id): self.connected(id, join)
            case .failure(let failure): self.fail(failure)
            }
        }
    }

    private func connected(_ id: String, _ join: String?) {
        if closed { return }
        uid = id
        root = config.sport == .squash ? "minikSquash" : "minikBeachVolley"
        directoryPath = root + "/publicTournaments"
        if join == "PUBLIC" {
            browse()
            return
        }
        if let join = join {
            code = join.uppercased()
        } else {
            let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
            code = String((0..<6).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
        }
        if !SportsOnline.isRoomCode(code) {
            error(tr("Enter a six-character code.", "הזינו קוד בן שישה תווים."))
            return
        }
        roomPath = root + "/rooms/" + code
        roomReady = true
        if join == nil { create() } else { enter() }
    }

    /// Android `Regex("[A-Z2-9]{6}")`.
    nonisolated static func isRoomCode(_ value: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ23456789")
        return value.count == 6 && value.allSatisfy { allowed.contains($0) }
    }

    private func member(_ slot: Int) -> Node {
        return ["character": avatar, "name": Characters.get(avatar).name(host?.hebrew ?? false), "rankPoints": points, "slot": slot,
                "ready": false, "connected": true, "receptionSlow": host?.receptionSlow() ?? true]
    }

    private func create() {
        guard let db = database, let configText = SportsCodec.text(SportsCodec.config(config)) else { return }
        let now = SportsClock.currentTimeMillis()
        let metaNode: Node = ["host": uid, "phase": "lobby", "config": configText, "leaseUntil": NSNumber(value: now + 10000), "epoch": 1,
                              "round": 1, "rounds": rounds, "public": publicCup]
        let value: Node = ["meta": metaNode, "members": [uid: member(0)] as Node, "slots": ["0": uid] as Node]
        db.set(roomPath, value) { [weak self] failure in
            guard let self = self else { return }
            if let failure = failure {
                self.fail(failure)
                return
            }
            self.listen()
            if self.publicCup { self.publishListing() }
        }
    }

    private func enter() {
        guard let db = database else { return }
        db.get(path("meta")) { [weak self] failure, value, exists in
            guard let self = self, !self.closed else { return }
            if let failure = failure {
                self.fail(failure)
                return
            }
            if !exists {
                self.error(self.tr("Room not found.", "החדר לא נמצא."))
                return
            }
            self.meta = NodeValue.node(value)
            guard let shared = NodeJSON.node(NodeValue.text(self.meta["config"] ?? "")), var joined = try? SportsCodec.config(shared) else {
                self.error(self.tr("Could not connect. Check your connection and try again.", "לא ניתן להתחבר. בדקו את החיבור ונסו שוב."))
                return
            }
            joined.challengeStep = -1
            self.config = joined
            db.get(self.path("members/" + self.uid)) { [weak self] failure, _, exists in
                // Android has no failure listener on this read.
                guard let self = self, !self.closed, failure == nil else { return }
                if exists {
                    self.listen()
                } else if NodeValue.text(self.meta["phase"] ?? "null") != "lobby" {
                    self.error(self.tr("This match has already started.", "המשחק כבר התחיל."))
                } else {
                    self.claim(0)
                }
            }
        }
    }

    private func claim(_ slot: Int) {
        let limit = config.sport == .squash ? 2 : config.teamSize * 2
        if slot >= limit {
            error(tr("This room is full.", "החדר מלא."))
            return
        }
        guard let db = database else { return }
        let me = uid
        db.transaction(path("slots/\(slot)"), { current in
            if let current = current, !(current is NSNull), (current as? String) != me { return .abort }
            return .commit(me)
        }, { [weak self] failure, committed, _ in
            guard let self = self else { return }
            if let failure = failure {
                self.fail(failure)
                return
            }
            if !committed {
                self.claim(slot + 1)
                return
            }
            db.set(self.path("members/" + self.uid), self.member(slot)) { [weak self] failure in
                guard let self = self else { return }
                if let failure = failure { self.fail(failure) } else { self.listen() }
            }
        })
    }

    // MARK: Listening

    private func listen() {
        guard let db = database else { return }
        db.set(path("members/\(uid)/receptionSlow"), host?.receptionSlow() ?? true, nil)
        db.onDisconnectSet(path("members/\(uid)/connected"), false)
        db.set(path("members/\(uid)/connected"), true, nil)
        watch("meta") { [weak self] n in
            guard let self = self else { return }
            self.meta = n
            self.phase = NodeValue.text(n["phase"] ?? "null")
            self.authority = NodeValue.text(n["host"] ?? "null") == self.uid
            self.view?.authority = self.authority
            self.syncRole()
            self.showLobby()
            self.recover()
        }
        watch("members") { [weak self] n in
            guard let self = self else { return }
            var fresh: [String: Node] = [:]
            for (id, value) in n { fresh[id] = NodeValue.node(value) }
            if self.phase == "lobby" {
                if fresh.count > self.members.count && fresh.count > 1 { self.host?.sound("connected") }
                let newlyReady = fresh.contains { id, m in
                    id != self.uid && NodeValue.bool(m["ready"]) == true && NodeValue.bool(self.members[id]?["ready"]) != true
                }
                if newlyReady { self.host?.sound("player_ready") }
            }
            self.members = fresh
            self.memberOrder = JavaOrder.hashMapOrder(Array(fresh.keys))
            self.showLobby()
            if self.authority && self.phase == "lobby" && NodeValue.bool(self.meta["public"]) == true { self.publishListing() }
        }
        watch("world") { [weak self] n in
            guard let self = self, let encoded = n["snapshot"] as? String, let j = NodeJSON.node(encoded) else { return }
            self.latest = j
            if self.world == nil || self.world?.matchId != j.optString("matchId") {
                self.world = nil
                self.finishing = false
                self.recover()
            } else if !self.authority, let w = self.world {
                if (try? SportsCodec.apply(w, j)) != nil {
                    self.view?.replicaAge = 0.0
                    self.view?.setNeedsDisplay()
                }
            }
        }
        watch("results") { [weak self] n in
            guard let self = self else { return }
            let previous = self.results
            var fresh: [String: Node] = [:]
            for (id, value) in n { fresh[id] = NodeValue.node(value) }
            self.results = fresh
            if !SportsOnline.same(previous, fresh) { self.host?.refreshOnlineResult() }
            if let e = self.world, let r = self.results[e.matchId], e.phase != .finished {
                e.scores[0] = KotlinNumber.int(NodeValue.number(r["a"]) ?? 0)
                e.scores[1] = KotlinNumber.int(NodeValue.number(r["b"]) ?? 0)
                e.winner = KotlinNumber.int(NodeValue.number(r["winner"]) ?? -1)
                e.phase = .finished
                self.view?.setNeedsDisplay()
            }
        }
        startPump()
    }

    private static func same(_ a: [String: Node], _ b: [String: Node]) -> Bool {
        return NSDictionary(dictionary: a).isEqual(to: b)
    }

    private func watch(_ child: String, _ callback: @escaping @MainActor (Node) -> Void) {
        guard let db = database else { return }
        let token = db.observe(path(child), { [weak self] value in
            guard let self = self, !self.closed else { return }
            callback(NodeValue.node(value))
        }, { [weak self] failure in
            guard let self = self, !self.closed else { return }
            self.fail(failure)
        })
        watchers.append(token)
    }

    private func sortedMembers() -> [(String, Node)] {
        let ordered = memberOrder.compactMap { id -> (String, Node)? in
            guard let n = members[id] else { return nil }
            return (id, n)
        }
        return ordered.stableSorted { a, b in
            KotlinNumber.int(NodeValue.number(a.1["slot"]) ?? 0) < KotlinNumber.int(NodeValue.number(b.1["slot"]) ?? 0)
        }
    }

    private func participants() -> [Participant] {
        return sortedMembers().enumerated().map { i, entry in
            let n = entry.1
            return Participant(entry.0, NodeValue.text(n["character"] ?? "null"), i % 2, false, NodeValue.text(n["name"] ?? "null"),
                               KotlinNumber.int(NodeValue.number(n["rankPoints"]) ?? 0))
        }
    }

    private func showLobby() {
        if phase != "lobby" || members.isEmpty { return }
        let key = (NodeJSON.string(members as Node) ?? "") + String(authority)
        if key == signature { return }
        signature = key
        let ready = Set(members.filter { NodeValue.bool($0.value["ready"]) == true }.map { $0.key })
        host?.lobby(code, participants(), ready, authority, self)
    }

    func ready() {
        guard roomReady, let db = database else { return }
        db.set(path("members/\(uid)/ready"), true) { [weak self] failure in
            if let failure = failure { self?.fail(failure) }
        }
    }

    func start() {
        if !authority || starting || phase != "lobby" { return }
        // A host alone in the room (house players fill the rest) may start without pressing Ready.
        let alone = members.count == 1
        let own = uid
        if members.contains(where: { entry in
            (NodeValue.bool(entry.value["ready"]) != true && !(alone && entry.key == own)) || NodeValue.bool(entry.value["connected"]) != true
        }) {
            error(tr("Everyone must be ready first.", "כולם צריכים להיות מוכנים קודם."))
            return
        }
        guard let db = database else { return }
        starting = true
        let me = uid
        db.transaction(path("meta"), { current in
            guard var d = current as? [String: Any], (d["host"] as? String) == me, (d["phase"] as? String) == "lobby" else { return .abort }
            d["phase"] = "starting"
            return .commit(d)
        }, { [weak self] failure, committed, _ in
            guard let self = self else { return }
            self.starting = false
            if !committed {
                if let failure = failure { self.fail(failure) }
                return
            }
            if NodeValue.bool(self.meta["public"]) == true { db.remove(self.directoryPath + "/" + self.code) }
            self.makeWorld()
        })
    }

    private func makeWorld() {
        guard let db = database else { return }
        var roster = participants()
        let capacity = config.sport == .squash ? 2 : config.teamSize * 2
        let available = Characters.forSport(config.sport).filter { c in !roster.contains { $0.character == c.id } }
        var b = 0
        while roster.count < capacity {
            let team = roster.filter({ $0.team == 0 }).count < capacity / 2 ? 0 : 1
            let slot = roster.filter({ $0.team == team }).count - (team == 0 ? 1 : 0)
            let index = team == 0 ? slot : config.teamSize - 1 + slot
            let selected: String? = index >= 0 && index < config.houseRoster.count ? config.houseRoster[index] : nil
            let c = selected != nil ? Characters.get(selected!) : available[b % available.count]
            roster.append(Participant("house-\(b)", c.id, team, true))
            b += 1
        }
        guard SportsEngine.validRoster(roster, config) else {
            error(tr("Could not connect. Check your connection and try again.", "לא ניתן להתחבר. בדקו את החיבור ונסו שוב."))
            return
        }
        let e = SportsEngine(config, roster, matchId: code + "-" + UUID().uuidString.lowercased())
        world = e
        let snapshot = SportsCodec.encode(e)
        latest = snapshot
        let now = SportsClock.currentTimeMillis()
        let values: Node = ["world": ["snapshot": SportsCodec.text(snapshot) ?? "{}", "at": db.serverTimestamp] as Node, "meta/phase": "playing",
                            "meta/leaseUntil": NSNumber(value: now + 10000)]
        db.update(roomPath, values) { [weak self] failure in
            guard let self = self else { return }
            if let failure = failure {
                self.fail(failure)
                return
            }
            self.host?.present(e, self.uid, self)
        }
    }

    private func recover() {
        if world != nil || (phase != "playing" && phase != "finished") { return }
        guard let j = latest, let e = try? SportsCodec.decode(j, allowPractice: false) else { return }
        world = e
        restoreAck(j)
        host?.present(e, uid, self)
    }

    private func syncRole() {
        let next = NodeValue.text(meta["host"] ?? "null")
        if next == role { return }
        role = next
        if let token = commandsToken { database?.removeObserver(token) }
        commandsToken = nil
        guard authority, let db = database else { return }
        if let j = latest {
            if let w = world { try? SportsCodec.apply(w, j) }
            restoreAck(j)
        }
        commandsToken = db.observeChildren(path("commands"), { [weak self] sender, value in
            guard let self = self, !self.closed else { return }
            self.processCommands(sender, value)
        }, { [weak self] failure in
            guard let self = self, !self.closed else { return }
            self.fail(failure)
        })
    }

    private func processCommands(_ sender: String, _ value: Any?) {
        // Android removes the listener on losing authority; events already queued here are dropped.
        guard authority, commandsToken != nil else { return }
        let commands = NodeValue.node(value)
        for nonce in commands.keys.sorted(by: JavaOrder.firebaseKeyPrecedes) {
            let key = sender + "/" + nonce
            if acceptedSet.contains(key) { continue }
            let n = NodeValue.node(commands[nonce])
            guard let e = world else { continue }
            let x = NodeValue.number(n["x"]) ?? 0.0
            let y = NodeValue.number(n["y"]) ?? 0.0
            let p = NodeValue.number(n["power"]) ?? 0.5
            if members[sender] != nil && (n["matchId"] as? String) == e.matchId {
                e.command(sender, nonce, NodeValue.text(n["kind"] ?? "null"), x, y, p, questionId: n["questionId"] as? String)
                accept(key)
                while acceptedOrder.count > 256 { acceptedSet.remove(acceptedOrder.removeFirst()) }
            }
        }
    }

    func command(_ kind: String, _ x: Double, _ y: Double, _ power: Double) {
        guard !closed, let w = world, let db = database else { return }
        commandSeq += 1
        let nonce = prefix + "-" + String(commandSeq)
        let questionId = w.answerFor(uid)?.question.id ?? ""
        let n: Node = ["matchId": w.matchId, "kind": kind, "questionId": questionId, "x": x, "y": y, "power": power,
                       "at": NSNumber(value: SportsClock.currentTimeMillis())]
        if !pendingOrder.contains(nonce) { pendingOrder.append(nonce) }
        // Remote presentation extrapolates motion; authoritative contacts and scores are applied once.
        if authority {
            w.command(uid, nonce, kind, x, y, power, questionId: questionId)
            accept(uid + "/" + nonce)
        }
        db.set(path("commands/\(uid)/\(nonce)"), n) { [weak self] failure in
            if let failure = failure { self?.fail(failure) }
        }
    }

    private func restoreAck(_ j: Node) {
        guard let a = j.optArray("acks") else { return }
        for item in a { accept(NodeValue.text(item)) }
    }

    // MARK: Pump

    private func startPump() {
        if pumpTask != nil { return }
        pumpTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self, !self.closed else { return }
                self.cycle()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func cycle() {
        guard roomReady, let db = database else { return }
        tick += 1
        if authority, let e = world {
            for (id, n) in members where e.receptionSlowEnabled[id] != nil {
                e.receptionSlowEnabled[id] = NodeValue.bool(n["receptionSlow"]) ?? true
            }
        }
        if authority && foreground && phase == "lobby" && NodeValue.bool(meta["public"]) == true && tick % 200 == 0 { publishListing() }
        if authority && foreground {
            if tick % 2 == 0 && !writing, let e = world {
                var j = SportsCodec.encode(e)
                j["acks"] = acceptedOrder
                latest = j
                writing = true
                let value: Node = ["snapshot": SportsCodec.text(j) ?? "{}", "at": db.serverTimestamp]
                db.set(path("world"), value) { [weak self] _ in self?.writing = false }
                if e.phase == .finished { finish(e) }
            }
            if tick % 40 == 0 { db.set(path("meta/leaseUntil"), NSNumber(value: SportsClock.currentTimeMillis() + 10000), nil) }
        }
        if tick % 20 == 0, let ack = latest?.optArray("acks") {
            let keys = Set(ack.map { NodeValue.text($0) })
            for nonce in pendingOrder where keys.contains(uid + "/" + nonce) {
                db.remove(path("commands/\(uid)/\(nonce)"))
            }
            pendingOrder.removeAll { keys.contains(uid + "/" + $0) }
        }
        if !authority && foreground && !claiming && phase == "playing",
           let lease = NodeValue.int64(meta["leaseUntil"]), lease < SportsClock.currentTimeMillis() {
            claiming = true
            let me = uid
            db.transaction(path("meta"), { current in
                guard var d = current as? [String: Any] else { return .abort }
                let now = SportsClock.currentTimeMillis()
                let expiry = NodeValue.int64(d["leaseUntil"]) ?? Int64.max
                if expiry >= now { return .abort }
                d["host"] = me
                d["leaseUntil"] = NSNumber(value: now + 10000)
                d["epoch"] = (NodeValue.number(d["epoch"]).map { KotlinNumber.int($0) } ?? 0) + 1
                return .commit(d)
            }, { [weak self] _, _, _ in
                self?.claiming = false
            })
        }
    }

    func finish(_ e: SportsEngine) {
        if closed || !authority || finishing || world?.matchId != e.matchId || e.phase != .finished { return }
        guard let db = database else { return }
        finishing = true
        let result: Node = ["matchId": e.matchId, "winner": e.winner, "a": e.scores[0], "b": e.scores[1], "authority": uid]
        db.transaction(path("results/" + e.matchId), { current in
            if let current = current, !(current is NSNull) { return .abort }
            return .commit(result)
        }, { [weak self] failure, _, _ in
            guard let self = self else { return }
            if let failure = failure {
                self.finishing = false
                self.fail(failure)
            } else if !self.closed && self.world?.matchId == e.matchId {
                db.set(self.path("meta/phase"), "finished", nil)
            }
        })
    }

    func nextRound() {
        if !authority || round >= totalRounds || world?.phase != .finished { return }
        guard let db = database else { return }
        let me = uid
        let next = round + 1
        db.transaction(path("meta"), { current in
            guard var d = current as? [String: Any], (d["host"] as? String) == me, (d["phase"] as? String) == "finished" else { return .abort }
            d["round"] = next
            d["phase"] = "starting"
            return .commit(d)
        }, { [weak self] failure, committed, _ in
            guard let self = self else { return }
            if committed {
                self.world = nil
                self.latest = nil
                self.clearAccepted()
                self.pendingOrder.removeAll()
                self.finishing = false
                self.config.seed = Int(Int32(truncatingIfNeeded: self.config.seed &+ 1))
                self.makeWorld()
            } else if let failure = failure {
                self.fail(failure)
            }
        })
    }

    func setForeground(_ on: Bool) {
        foreground = on
        if roomReady { database?.set(path("members/\(uid)/connected"), on, nil) }
    }

    private func publishListing() {
        if closed || !roomReady { return }
        guard let db = database else { return }
        let value: Node = ["rounds": min(max(rounds, 3), 5), "capacity": config.sport == .squash ? 2 : config.teamSize * 2,
                           "count": max(members.count, 1), "updatedAt": db.serverTimestamp]
        db.set(directoryPath + "/" + code, value) { [weak self] failure in
            if let failure = failure { self?.fail(failure) }
        }
    }

    private func browse() {
        guard let db = database else { return }
        let since = Double(SportsClock.currentTimeMillis() - 900000)
        publicToken = db.observeQuery(directoryPath, orderBy: "updatedAt", startAt: since, limit: 50, { [weak self] rows in
            guard let self = self, !self.closed else { return }
            var entries: [(String, Int, String)] = []
            for (key, value) in rows {
                let n = NodeValue.node(value)
                let count = NodeValue.number(n["count"]).map { KotlinNumber.int($0) } ?? 0
                let capacity = NodeValue.number(n["capacity"]).map { KotlinNumber.int($0) } ?? 0
                if count >= capacity { continue }
                entries.append((key, NodeValue.number(n["rounds"]).map { KotlinNumber.int($0) } ?? 3, "\(count)/\(capacity)"))
            }
            self.host?.publicTournaments(entries)
        }, { [weak self] failure in
            guard let self = self, !self.closed else { return }
            self.fail(failure)
        })
    }

    func close() {
        closed = true
        pumpTask?.cancel()
        pumpTask = nil
        if let token = publicToken { database?.removeObserver(token) }
        publicToken = nil
        for token in watchers { database?.removeObserver(token) }
        watchers.removeAll()
        if let token = commandsToken { database?.removeObserver(token) }
        commandsToken = nil
        if roomReady && !uid.isEmpty { database?.set(path("members/\(uid)/connected"), false, nil) }
        view = nil
    }

    private func fail(_ failure: Error) {
        NSLog("SportsOnline: room operation failed: %@", String(describing: failure))
        if !closed { error(tr("Could not connect. Check your connection and try again.", "לא ניתן להתחבר. בדקו את החיבור ונסו שוב.")) }
    }
}
