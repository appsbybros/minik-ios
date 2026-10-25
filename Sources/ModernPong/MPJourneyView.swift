import SwiftUI
import Combine
import StoreKit
import UIKit

/// Android `PongJourneyActivity` (29f5dc7): the daily skill journey, local team play, the settings page and the online
/// team entry. No ads run here, as on Android.
@MainActor final class MPJourneyController: ObservableObject {
    enum Page { case brief, list, teams, game, result, settings, online }
    @Published private(set) var page = Page.brief
    @Published private(set) var game: MPPlay?
    @Published var mode = MPTeamMode.alternate
    @Published var ids = ["miniko", "minik", "mia", "june"]
    @Published private(set) var hud = ""
    @Published private(set) var hudScore: AttributedString?
    @Published private(set) var hint = ""
    /// Android `PongHelpTips.align`: the double-bounce tip reads from the start edge.
    @Published private(set) var hintIsTip = false
    @Published private(set) var running = false
    /// Android `PongInstructionDialog`: title and message of the open instructions (the message is composed once,
    /// because it may count one showing of the "Did you know?" tip).
    @Published private(set) var instructions: (game: MPPlay, title: String, message: String)?
    /// Team rules dialog: true starts a match, false practises the skill.
    @Published var teamBrief: Bool?
    @Published var picking: Int?
    @Published var notice: String?
    @Published var gate: (() -> Void)?
    @Published var share: MPShareItem?
    @Published private(set) var online: MPOnlineTeamsController?
    @Published private(set) var resultWon = false
    /// Android team setup: control difficulty (`teamControl`, ControlChoice 4/1/0/3) and arena (`teamArena`).
    @Published var teamControl = 0 { didSet { defaults.set(teamControl, forKey: MPJourneyController.prefix + "teamControl") } }
    @Published var teamArena = MPArena.beach { didSet { defaults.set(teamArena.wire, forKey: MPJourneyController.prefix + "teamArena") } }
    /// Android `teamSeed`: one seed per team-colour pairing; Play again draws a new one.
    @Published private(set) var teamSeed = Int64.random(in: Int64.min...Int64.max)
    var hebrew = false
    var identity: MPIdentity?
    var onExit: (() -> Void)?
    private var resumed = true, handled = false
    private var onlineWatch: AnyCancellable?
    private let defaults = UserDefaults.standard
    private let resultAudio = MPAudio()
    private static let prefix = "modern.pong.journey."
    static var soundsOn: Bool { (UserDefaults.standard.object(forKey: prefix + "sounds") as? Bool) ?? true }
    static var musicOn: Bool { (UserDefaults.standard.object(forKey: "modern.pong.music.enabled") as? Bool) ?? true }
    var step: Int { defaults.integer(forKey: MPJourneyController.prefix + "step") }
    var stars: Int { defaults.integer(forKey: MPJourneyController.prefix + "stars") }
    var hasSaved: Bool { defaults.string(forKey: MPJourneyController.prefix + "saved") != nil }
    func tr(_ en: String, _ he: String) -> String { hebrew ? he : en }
    /// Android `PongTeamColors.score` for SwiftUI: "a : b", each number in its team colour, the separator white.
    /// `palette` (Android f0ea4aa): the table's earned colours.
    static func teamScore(_ first: Int, _ second: Int, firstTeam: Int = 0, seed: Int64, palette: MPTeamColors.Palette? = nil) -> AttributedString {
        var a = AttributedString(String(first)), gap = AttributedString(" : "), b = AttributedString(String(second))
        a.foregroundColor = MPColor.color(palette?.fill(firstTeam) ?? MPTeamColors.fill(firstTeam, seed: seed)); gap.foregroundColor = .white
        b.foregroundColor = MPColor.color(palette?.fill(1 - firstTeam) ?? MPTeamColors.fill(1 - firstTeam, seed: seed))
        return a + gap + b
    }
    /// Android f0ea4aa `PongTeamColors.local(PongRanking.rank.color, seed)`: a local team table keeps the player's
    /// earned colour for their team.
    static func localPalette(_ seed: Int64) -> MPTeamColors.Palette { MPTeamColors.local(MPRanking().rank.color, seed: seed) }
    /// Android `levels`: the order of the control choices in the team setup.
    static let controlLevels = [4, 1, 0, 3]

    func open(_ page: Page, identity: MPIdentity?, hebrew: Bool) {
        self.identity = identity; self.hebrew = hebrew
        // Android onCreate: a step saved with the 30-stage catalog keeps its cycle and stage.
        let p = MPJourneyController.prefix, old = (defaults.object(forKey: p + "catalogSize") as? Int) ?? 30
        if old != MPJourney.count {
            defaults.set(MPJourney.migrateStep(step, max(old, 1)), forKey: p + "step"); defaults.set(MPJourney.count, forKey: p + "catalogSize")
        }
        // Android: the player's avatar first, then the roster order.
        let avatar = MPRoster.find(identity?.characterId ?? "")?.id ?? "miniko"
        ids = Array(([avatar] + MPRoster.all.map(\.id).filter { $0 != avatar }).prefix(4))
        teamControl = MPControlChoice.normalize((defaults.object(forKey: p + "teamControl") as? Int) ?? 0)
        teamArena = MPArena.read(defaults.string(forKey: p + "teamArena") ?? "beach")
        switch page {
        case .teams: teamSetup()
        case .settings: settings()
        default: brief()
        }
    }
    var title: String {
        switch page {
        case .brief: return tr("Daily skill journey", "אתגר יומי")
        case .list: return tr("Your journey", "המסע שלכם")
        case .teams: return tr("Play as a team", "משחק קבוצתי")
        case .game: return game?.stage.map { $0.title(hebrew) } ?? tr("Team match", "משחק קבוצתי")
        case .result:
            guard let g = game else { return "" }
            if g.stage == nil { return resultWon ? tr("You won!", "ניצחתם!") : tr("Match complete", "המשחק הסתיים") }
            return resultWon ? tr("Challenge complete!", "האתגר הושלם!") : tr("Let's try again", "מנסים שוב")
        case .settings: return tr("Settings", "הגדרות")
        case .online: return online?.title ?? tr("Online team game", "משחק קבוצתי ברשת")
        }
    }
    /// Android `navigateBack`: the game returns to its setup or briefing, the list to the briefing.
    func back() {
        switch page {
        case .game:
            let wasTeam = game?.stage == nil
            save(); game = nil; running = false; instructions = nil
            if wasTeam { teamSetup() } else { brief() }
        case .list: brief()
        case .online: online?.back()
        default: leave()
        }
    }
    func leave() {
        save(); online?.close(); online = nil; game = nil; running = false; instructions = nil; resultAudio.stop()
        onExit?()
    }
    func lifecycle(active: Bool) {
        resumed = active
        if !active { save(); resultAudio.stop() }
        running = active && page == .game && game?.paused == false
        online?.lifecycle(active: active)
    }
    private func save() {
        guard let g = game else { return }
        if !g.ended, let body = MPJSON.encode(g.save()) { defaults.set(body, forKey: MPJourneyController.prefix + "saved") }
        else { defaults.removeObject(forKey: MPJourneyController.prefix + "saved") }
    }
    func brief() { page = .brief; game = nil; running = false }
    func journeyList() { page = .list }
    func settings() { page = .settings }
    func teamSetup() { page = .teams; game = nil; running = false }
    func resume() {
        if let body = defaults.string(forKey: MPJourneyController.prefix + "saved"), let restored = try? MPPlay.restore(MPJSON.decode(body)) { play(restored) }
        else { defaults.removeObject(forKey: MPJourneyController.prefix + "saved"); brief() }
    }
    func paintPlayground() { play(MPPlay(roster: ids, openPaint: true)) }
    func startJourney(_ step: Int) {
        let s = MPJourney.stage(step)
        var used: Set<String> = [ids[0]], roster = [ids[0]]
        for _ in 0..<3 { let b = s.partner(step / MPJourney.count, exclude: used); used.insert(b.id); roster.append(b.id) }
        // Android c9f5fa6: practice starts directly; the instructions stay one tap away.
        play(MPPlay(step: step, roster: roster))
    }
    func play(_ g: MPPlay) {
        game = g; page = .game; handled = false; hud = ""; hudScore = nil; hint = ""
        running = resumed && !g.paused
        frame()
    }
    func startTeam() { play(MPPlay(mode: mode, roster: ids, seed: teamSeed, arena: teamArena.wire, control: teamControl)) }
    func practiseTeamSkill() { startJourney(mode == .alternate ? 15 : 16) }
    /// Android `teamBrief`: the stage's team briefing plus the controls and the match rule.
    var teamBriefing: String {
        MPJourney.stages[mode == .alternate ? 15 : 16].briefing(hebrew) + "\n\n" + tr("Starter gives more time to prepare an aimed swipe. Standard: tap or swipe as the ball approaches your paddle. Outside that window, drag to move. Beginner assists the hit. Pro: swipe to aim; an arc adds topspin and a left–right sweep adds sidespin. First team to 7 wins.", "בנינוחה אפשר להכין החלקה מכוונת מוקדם יותר. ברגילה מקישים או מחליקים כשהכדור מתקרב למחבט. מחוץ לחלון הזה גוררים כדי לזוז. במתחילים החבטה נעשית בסיוע. במקצועני מחליקים כדי לכוון: קשת מוסיפה סיבוב קדמי ותנועת שמאל–ימין מוסיפה סיבוב צדי. הקבוצה הראשונה שתגיע ל־7 מנצחת.")
    }
    /// Each place needs a different character (Android shows a short notice).
    func choose(_ index: Int, _ id: String) {
        if ids.enumerated().contains(where: { $0.offset != index && $0.element == id }) {
            notice = tr("Choose a different character for each place", "בחרו דמות אחרת לכל מקום")
        } else { ids[index] = id }
    }
    func showInstructions(_ g: MPPlay) {
        g.paused = true; running = false; frame()
        let title = g.stage.map { $0.title(hebrew) } ?? tr("Team match", "משחק קבוצתי")
        // Android c9f5fa6: the briefing, then only the control in use and its explanation.
        let controls = tr("Control difficulty: ", "רמת השליטה: ") + MPControlChoice.title(g.controls[0], hebrew: hebrew) + "\n" + MPControlChoice.explanation(g.controls[0], hebrew: hebrew)
        let message = (g.stage?.briefing(hebrew) ?? MPJourney.stages[g.alternate ? 15 : 16].briefing(hebrew)) + "\n\n" + controls
        instructions = (g, title, message)
    }
    func closeInstructions() {
        instructions?.game.paused = false; instructions = nil
        running = resumed && page == .game && game?.paused == false; frame()
    }
    func togglePause() {
        guard let g = game else { return }
        g.paused.toggle(); running = !g.paused && resumed; frame()
    }
    /// Android `refresh`: the score line, the advice line and the end of a challenge.
    func frame() {
        guard let g = game, page == .game else { return }
        let score: String
        if g.stage?.territory == true { score = "\(Int(g.remaining))s · \(Int(g.paint.coverage(0) * 100))% : \(Int(g.paint.coverage(1) * 100))%" }
        else if g.stage == nil { score = "\(g.points[0]) : \(g.points[1])" }
        else if g.openPaint { score = "★ \(g.successes)" }
        else { score = "\(g.successes) / \(g.goal)  · " + tr("Misses", "החטאות") + " \(g.mistakes)" }
        if hud != score {
            hud = score
            // Team scores are drawn in the two team colours.
            hudScore = g.stage == nil ? MPJourneyController.teamScore(g.points[0], g.points[1], seed: g.seed, palette: MPJourneyController.localPalette(g.seed)) : nil
        }
        let advice: String
        if g.paused { advice = tr("Paused", "מושהה") }
        else if let ending = g.ending { advice = ending.message(hebrew) }
        // Android c9f5fa6: a practice stage names its control difficulty.
        else if g.stage != nil { advice = tr("Control difficulty: ", "רמת השליטה: ") + MPControlChoice.title(g.controls[0], hebrew: hebrew) }
        else if g.stage?.skill == .serve { advice = tr("Land the serve inside the golden island", "הנחיתו את ההגשה בתוך האי הזהוב") }
        else if g.waitingServe { advice = tr("Tap the far side to serve", "הקישו בצד הרחוק כדי להגיש") }
        else if g.team && g.alternate && g.nextHitter[0] != 0 { advice = tr("Your teammate’s turn. Drag aside to make room.", "תור חבר הקבוצה. גררו הצדה כדי לפנות מקום.") }
        else if g.stage?.standard == true { advice = tr("Move into reach, then swipe toward the golden target", "התמקמו בטווח המחבט, ואז החליקו לכיוון היעד הזהוב") }
        else if g.targeted { advice = tr("Drag toward the ball, then tap the golden target", "גררו לכדור, ואז הקישו על היעד הזהוב") }
        else if g.controls[0] == 3 { advice = tr("Drag your character to move · swipe on the table to return · curve for spin", "גררו את הדמות כדי לזוז · החליקו על השולחן לחבטה · קשת לסיבוב") }
        else { advice = tr("Drag to move. As the ball approaches, tap or swipe to return.", "גררו כדי לזוז. כשהכדור מתקרב, הקישו או החליקו לחבטה.") }
        let shown: String
        if g.notice.hasPrefix("diagonal-serve-") { shown = MPHelpTips.diagonal(he: hebrew, ownPoint: g.notice == "diagonal-serve-1") }
        else if g.notice == "serve-double-bounce-0" && g.showServePointTip { shown = MPHelpTips.serveDoubleBouncePoint(he: hebrew) }
        else { shown = advice }
        if hint != shown { hint = shown }
        let tip = g.notice.hasPrefix("serve-double-bounce-")
        if hintIsTip != tip { hintIsTip = tip }
        if g.ended && g.ending == nil && !handled {
            handled = true; running = false
            Task { @MainActor [weak self] in self?.result(g) }
        }
    }
    @Published private(set) var resultText = ""
    /// Android `winning-team` caption: "You and Minik won!" / "<pair> won!" (Hebrew "אתם ניצחתם!" for the player's team).
    @Published private(set) var winningTeam: String?
    private func result(_ g: MPPlay) {
        guard game === g else { return }
        page = .result; resultWon = g.won
        defaults.removeObject(forKey: MPJourneyController.prefix + "saved")
        let p = MPJourneyController.prefix
        if g.won, let stage = g.stage, g.step == step {
            let receipt = "\(g.step / MPJourney.count)/" + stage.id
            var receipts = Set(defaults.stringArray(forKey: p + "receipts") ?? [])
            if receipts.insert(receipt).inserted {
                // Android 96ae066: a new completion also pays colour-rank points once.
                MPRanking().award("daily/" + receipt, MPRanks.daily(g.step))
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                let bonus = defaults.string(forKey: p + "day") != today ? 30 : 0
                defaults.set(Array(receipts), forKey: p + "receipts"); defaults.set(today, forKey: p + "day")
                defaults.set(stars + 40 + g.cycle * 10 + bonus, forKey: p + "stars"); defaults.set(MPJourney.nextStep(g.step), forKey: p + "step")
            }
        }
        if g.won && MPJourneyController.soundsOn { resultAudio.play("minik_claps") }
        if g.stage == nil {
            let winner = g.points[0] > g.points[1] ? 0 : 1
            let names = g.actors.enumerated().filter { $0.element.team == winner }.map { i, a in
                i == 0 ? tr("You", "אתם") : (MPRoster.find(a.character) ?? MPRoster.all[0]).name(hebrew: hebrew)
            }
            let pair = names.map { "\u{2068}" + $0 + "\u{2069}" }.joined(separator: hebrew ? " ו" : " and ")
            winningTeam = hebrew ? (winner == 0 ? "אתם ניצחתם!" : pair + " ניצחו!") : pair + " won!"
        } else { winningTeam = nil }
        if g.stage == nil { resultText = tr("Final score: \(g.points[0]) : \(g.points[1])", "התוצאה: \(g.points[0]) : \(g.points[1])") }
        else if g.won { resultText = tr("Nice work. Your next skill is ready.", "כל הכבוד. המיומנות הבאה מחכה לכם.") }
        else { resultText = tr("Your progress is safe. Take your time and try again.", "ההתקדמות שלכם נשמרת. קחו את הזמן ונסו שוב.") }
    }
    var resultWinner: Int { game.map { $0.points[0] > $0.points[1] ? 0 : 1 } ?? 0 }
    var resultAction: String {
        guard let g = game else { return "" }
        if g.stage == nil { return tr("Play again", "משחק נוסף") }
        return g.won ? tr("Next briefing", "הסבר לאתגר הבא") : tr("Try again", "מנסים שוב")
    }
    func resultPrimary() {
        guard let g = game else { brief(); return }
        if g.stage == nil {
            // Android f0f27c4: replay the same teams, arena and control with a new colour pairing.
            teamSeed = Int64.random(in: Int64.min...Int64.max)
            play(MPPlay(mode: g.mode, roster: g.roster, seed: teamSeed, arena: g.arena, control: g.controls[0]))
        } else if g.won { brief() } else if g.step >= 0 { startJourney(g.step) } else { teamSetup() }
    }
    func openOnline() {
        let controller = MPOnlineTeamsController(mode: mode, identity: MPTeamIdentity.local(identity, hebrew: hebrew), hebrew: hebrew, arena: teamArena, control: teamControl)
        controller.onExit = { [weak self] in
            guard let self else { return }
            self.online?.close(); self.online = nil; self.teamSetup()
        }
        onlineWatch = controller.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        online = controller; page = .online
    }
    // MARK: Settings (Android "settings" page)
    func setSounds(_ on: Bool) { defaults.set(on, forKey: MPJourneyController.prefix + "sounds"); objectWillChange.send() }
    func setMusic(_ on: Bool) { defaults.set(on, forKey: "modern.pong.music.enabled"); objectWillChange.send() }
    func rateApp() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }
    static let storeLink = "https://miniklearn.com/apps/minik-ping-pong/"
    func shareApp() { share = MPShareItem(text: MPJourneyController.storeLink) }
    func sendFeedback() {
        var mail = URLComponents(); mail.scheme = "mailto"; mail.path = "appsbybros.dev@gmail.com"
        mail.queryItems = [URLQueryItem(name: "subject", value: "Minik Ping Pong feedback")]
        guard let url = mail.url else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            MainActor.assumeIsolated {
                guard let self, !opened else { return }
                self.notice = self.tr("No suitable app is installed", "לא מותקנת אפליקציה מתאימה")
            }
        }
    }
}

struct MPShareItem: Identifiable { let id = UUID(); let text: String }
struct MPShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Android journey colours: blue actions, aqua secondary actions, deep teal text on a pale panel.
enum MPJourneyStyle {
    static let ink = Color(red: 0x17 / 255, green: 0x3e / 255, blue: 0x56 / 255)
    static let gold = Color(red: 0xb8 / 255, green: 0xd9 / 255, blue: 1)
    static let cyan = Color(red: 0xb8 / 255, green: 0xee / 255, blue: 0xe4 / 255)
    static let panel = Color(red: 0xf5 / 255, green: 0xfc / 255, blue: 1).opacity(0xf2 / 255)
    static let hudBar = Color(red: 0x17 / 255, green: 0x3e / 255, blue: 0x56 / 255).opacity(0xe6 / 255)
    static let link = Color(red: 0x20 / 255, green: 0x5c / 255, blue: 0xa8 / 255)
    /// Android settings buttons (29f5dc7): Rate pink, Share yellow, Send feedback orange, each a raised face.
    static let rateFace = MPCourtFace(base: 0xffff5ba6, top: 0xffff85bd, middle: 0xffff5ba6, bottom: 0xffed4791)
    static let shareFace = MPCourtFace(base: 0xffffe079, top: 0xffffedaa, middle: 0xffffe079, bottom: 0xfff4c954)
    static let feedbackFace = MPCourtFace(base: 0xffffb46a, top: 0xffffd09b, middle: 0xffffb46a, bottom: 0xffef9849)
}

struct MPJourneyButton: View {
    let title: String
    var accent = false
    var fill: Color? = nil
    var textColor = MPJourneyStyle.ink
    /// A raised Android face (gradient), e.g. `MPCourtStyle.startFace`.
    var face: MPCourtFace? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(textColor).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 14)
                .background {
                    if let face { RoundedRectangle(cornerRadius: 22).fill(face.gradient) }
                    else { RoundedRectangle(cornerRadius: 22).fill(fill ?? (accent ? MPJourneyStyle.gold : MPJourneyStyle.cyan)) }
                }
        }.buttonStyle(.plain)
    }
}

/// A pale reading panel, at most 620 points wide (Android `ReadingPanel`).
struct MPJourneyPanel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 10) { content }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(MPJourneyStyle.panel, in: RoundedRectangle(cornerRadius: 28))
                .frame(maxWidth: 620).padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Android `SettingSelector`: a white rounded selector with a purple chevron (a native menu on iOS).
struct MPJourneySelector<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].label).tag(options[i].value) }
            }
        } label: {
            HStack {
                // Android 838c209: the selected value is 20 sp.
                Text(options.first { $0.value == selection }?.label ?? "").font(.system(size: 20, weight: .semibold)).foregroundStyle(MPJourneyStyle.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(red: 79 / 255, green: 53 / 255, blue: 126 / 255))
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(red: 151 / 255, green: 132 / 255, blue: 190 / 255), lineWidth: 1) }
        }
        .accessibilityLabel(title)
    }
}

/// Android `PongOrientationHint`: once per app run, a portrait court that has never been played in landscape
/// suggests the wider view (after 0.9 s, shown like a long toast). The once-per-run state is the process-wide
/// `MPLandscapeTipSession.shared`, which the singles court uses too (Android `PongOrientationHint.session`).
@MainActor final class MPOrientationHint: ObservableObject {
    static let shared = MPOrientationHint()
    @Published private(set) var visible = false
    func observe(wide: Bool) { MPLandscapeTipSession.shared.observe(wide); if wide { visible = false } }
    func schedule(active: @escaping () -> Bool, wide: @escaping () -> Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            observe(wide: wide())
            guard !wide(), MPLandscapeTipSession.shared.claim(active()) else { return }
            visible = true
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            visible = false
        }
    }
    func text(_ hebrew: Bool) -> String { hebrew ? "לתצוגה רחבה יותר, שחקו במצב אופקי." : "For a wider view, play in landscape." }
}

/// The toast of `MPOrientationHint`.
struct MPOrientationToast: View {
    @ObservedObject var hint = MPOrientationHint.shared
    let hebrew: Bool
    var body: some View {
        if hint.visible {
            Text(hint.text(hebrew)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10).background(Color.black.opacity(0.78), in: Capsule())
                .padding(.bottom, 32).frame(maxHeight: .infinity, alignment: .bottom).allowsHitTesting(false)
                .transition(.opacity).accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Android `safeContent(arena = …)` with `ArenaBackdrop`: game-only scenery behind a team match, aspect-filled (the
/// landscape beach keeps its shoreline above the far baseline) with a dark fade at the top for the white captions.
/// Original/Indoors keep the screen's own background; without the bundled art nothing is drawn. With `scenery` the
/// table moves it with the reception camera and draws the castle's foreground foliage over itself.
struct MPArenaBackdrop: View {
    let arena: MPArena
    var scenery: MPArenaScenery? = nil
    var body: some View { MPArenaBackdropLayer(arena: arena, scenery: scenery).ignoresSafeArea().accessibilityHidden(true) }
}

/// Android `ReceptionCamera.scenery` / `ArenaBackdrop.foreground`: how a team table finds the scenery behind it.
final class MPArenaScenery {
    fileprivate(set) weak var view: MPArenaBackdropView?
}

private struct MPArenaBackdropLayer: UIViewRepresentable {
    let arena: MPArena
    let scenery: MPArenaScenery?
    func makeUIView(context: Context) -> MPArenaBackdropView { MPArenaBackdropView() }
    func updateUIView(_ view: MPArenaBackdropView, context: Context) { view.arena = arena; scenery?.view = view }
}

final class MPArenaBackdropView: UIView {
    var arena = MPArena.legacy { didSet { if arena != oldValue { laidOut = nil; setNeedsLayout() } } }
    /// The castle's foreground foliage, cut from the scenery once per layout: images and their rects in this view.
    private(set) var foliage: [(UIImage, CGRect)] = []
    // A still copy under the moving one fills any edge the zoom uncovers (as `MPScene` does).
    private let still = CALayer(), camera = CALayer(), moving = CALayer(), shade = CAGradientLayer()
    private var laidOut: CGSize?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; backgroundColor = .clear; clipsToBounds = true
        camera.anchorPoint = .zero; camera.addSublayer(moving)
        shade.colors = [MPSinglesArena.captionShade.cgColor, UIColor.clear.cgColor]
        [still, camera, shade].forEach(layer.addSublayer)
    }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard laidOut != size else { return }
        laidOut = size
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        let wide = size.width > size.height
        let image = size.width > 1 && size.height > 1 ? arena.backdrop(wide: wide) : nil
        let rect = image.map { MPSinglesArena.destination($0.size, in: size, arena: arena) } ?? .zero
        for piece in [still, moving] { piece.contents = image?.cgImage; piece.frame = rect }
        camera.bounds = CGRect(origin: .zero, size: size); camera.position = .zero
        shade.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.25); shade.isHidden = image == nil
        foliage = image.map { image in
            MPSinglesArena.foliage(arena, wide: wide).compactMap { polygon in
                let path = UIBezierPath()
                for (i, p) in polygon.enumerated() {
                    let q = CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                path.close()
                let box = path.bounds.integral
                guard box.width >= 1, box.height >= 1 else { return nil }
                return (UIGraphicsImageRenderer(bounds: box).image { _ in path.addClip(); image.draw(in: rect) }, box)
            }
        } ?? []
    }
    /// Android `ReceptionCamera.scenery`: `offset` is the court's origin in this view.
    func follow(_ reception: MPReceptionCamera, offset: CGPoint) {
        let t = reception.transform(offset: offset)
        guard camera.affineTransform() != t else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true); camera.setAffineTransform(t); CATransaction.commit()
    }
}

struct MPJourneyScreen: View {
    @ObservedObject var journey: MPJourneyController
    @State private var scenery = MPArenaScenery()
    private var he: Bool { journey.hebrew }
    private func t(_ en: String, _ he: String) -> String { journey.tr(en, he) }
    /// Android c9f5fa6: body text reads from the start edge unless it is bold (`start = !bold`).
    private func text(_ value: String, size: CGFloat = 17, bold: Bool = false, start explicit: Bool? = nil) -> some View {
        let start = explicit ?? !bold
        return Text(value).font(.system(size: size, weight: bold ? .bold : .regular)).foregroundStyle(MPJourneyStyle.ink)
            .multilineTextAlignment(start ? .leading : .center).frame(maxWidth: .infinity, alignment: start ? .leading : .center)
            .padding(.vertical, 6).fixedSize(horizontal: false, vertical: true)
    }
    var body: some View {
        Group {
            switch journey.page {
            case .brief: brief
            case .list: list
            case .teams: teams
            case .game: game
            case .result: result
            case .settings: MPSettingsPage(journey: journey)
            case .online: if let online = journey.online { MPOnlineTeamsScreen(model: online) }
            }
        }
        .overlay {
            if let open = journey.instructions {
                MPInstructionDialog(title: open.title, message: open.message, hebrew: he) { journey.closeInstructions() }
            }
        }
        .alert(t("Two against two", "שניים מול שניים"), isPresented: Binding(get: { journey.teamBrief != nil }, set: { if !$0 { journey.teamBrief = nil } })) {
            let start = journey.teamBrief == true
            Button(start ? t("Play", "לשחק") : t("Practice this skill", "מתרגלים את המיומנות")) {
                journey.teamBrief = nil
                if start { journey.startTeam() } else { journey.practiseTeamSkill() }
            }
            Button(t("Cancel", "ביטול"), role: .cancel) { journey.teamBrief = nil }
        } message: { Text(journey.teamBriefing) }
        .alert(journey.notice ?? "", isPresented: Binding(get: { journey.notice != nil }, set: { if !$0 { journey.notice = nil } })) {
            Button(t("OK", "אישור")) { journey.notice = nil }
        }
        .sheet(isPresented: Binding(get: { journey.picking != nil }, set: { if !$0 { journey.picking = nil } })) {
            if let index = journey.picking {
                MPHousePickerSheet(hebrew: he, selected: journey.ids[index], picked: { id in journey.choose(index, id); journey.picking = nil },
                                   cancel: { journey.picking = nil })
            }
        }
        .sheet(item: $journey.share) { item in MPShareSheet(text: item.text) }
        .sheet(isPresented: Binding(get: { journey.gate != nil }, set: { if !$0 { journey.gate = nil } })) {
            ParentalGateView(onCancel: { journey.gate = nil }, onUnlock: {
                let action = journey.gate; journey.gate = nil
                Task { @MainActor in try? await Task.sleep(nanoseconds: 400_000_000); action?() }
            }).preferredColorScheme(.light)
        }
    }
    /// Android c9f5fa6: the stages of the current cycle (plus the current one), in catalogue order.
    private static func shown(_ step: Int) -> [Int] { Array(Set(MPJourney.available(step) + [step % MPJourney.count])).sorted() }
    /// Android c9f5fa6 `brief`: the stage number within this cycle, its control difficulty, the briefing and the partner.
    private var brief: some View {
        let n = journey.step, count = MPJourney.count, s = MPJourney.stage(n), partner = s.partner(n / count, exclude: [journey.ids[0]])
        let shown = MPJourneyScreen.shown(n), number = (shown.firstIndex(of: n % count) ?? n % count) + 1
        return MPJourneyPanel {
            // The stage counter always reads left to right.
            text(MPMatchText.ordered("\(number) / \(shown.count)"), size: 18, bold: true)
            text(s.title(he), size: 24, bold: true)
            text(t("Control difficulty: ", "רמת השליטה: ") + MPControlChoice.title(MPJourney.control(n), hebrew: he), size: 18, bold: true, start: true)
            text(s.briefing(he), start: true)
            text(t("Practice partner: ", "שותף לאימון: ") + partner.name(hebrew: he), size: 18, bold: true, start: true)
            MPAvatar(character: partner.id, icon: 0).frame(height: 110).accessibilityLabel(partner.name(hebrew: he))
            MPJourneyButton(title: t("Start challenge", "מתחילים באתגר"), face: MPCourtStyle.startFace) { journey.startJourney(n) }
            if journey.hasSaved { MPJourneyButton(title: t("Resume practice", "המשך אימון"), face: MPCourtStyle.startFace) { journey.resume() } }
            MPJourneyButton(title: t("Your journey", "המסע שלכם"), fill: MPColor.color(0xffa6dcff)) { journey.journeyList() }
            Text(t("Practice stars", "כוכבי אימון") + ": \(journey.stars)").font(.system(size: 16)).foregroundStyle(MPJourneyStyle.ink).frame(maxWidth: .infinity, minHeight: 72)
        }
    }
    /// Android c9f5fa6 `journeyList`: this cycle's control difficulty and its stages (Back returns to the briefing).
    private var list: some View {
        let step = journey.step, n = step % MPJourney.count, shown = MPJourneyScreen.shown(step)
        return MPJourneyPanel {
            text(t("Control difficulty: ", "רמת השליטה: ") + MPControlChoice.title(MPJourney.control(step), hebrew: he), size: 18, bold: true, start: true)
            text(t("Complete this journey to practise with the next control difficulty.", "משלימים את המסלול כדי להתאמן ברמת השליטה הבאה."), start: true)
            ForEach(Array(shown.enumerated()), id: \.element) { number, i in
                text((i < n ? "✓" : i == n ? "★" : "○") + " \(number + 1). " + MPJourney.stages[i].title(he), start: true)
            }
        }
    }
    private var teams: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    text(t("You and a house teammate against two house players", "אתם וחבר קבוצתכם מול שני שחקני בית"), size: 18, bold: true)
                    text(t("Team rules", "חוקי הקבוצה"), size: 19, bold: true)
                    MPJourneySelector(title: t("Team rules", "חוקי הקבוצה"), options: MPTeamMode.allCases.map { (value: $0, label: $0.title(he)) }, selection: $journey.mode)
                    text(journey.mode.explanation(he), size: 16)
                    text(t("Control difficulty", "רמת השליטה"), size: 19, bold: true)
                    MPJourneySelector(title: t("Control difficulty", "רמת השליטה"), options: MPJourneyController.controlLevels.map { (value: $0, label: MPJourneyScreen.controlTitle($0, he)) }, selection: $journey.teamControl)
                    // Android c9f5fa6: only the selected control is explained.
                    text(MPControlChoice.explanation(journey.teamControl, hebrew: he), size: 16)
                    text(t("Arena", "זירה"), size: 19, bold: true)
                    MPJourneySelector(title: t("Arena", "זירה"), options: MPArena.choices.map { (value: $0, label: $0.title(he: he)) }, selection: $journey.teamArena)
                    ForEach(1..<4, id: \.self) { i in
                        let role = i == 1 ? t("Your teammate", "חבר הקבוצה שלכם") : t("Opponent", "יריב") + " \(i - 1)"
                        // Android f0ea4aa: the player's team wears the earned colour; ink contrasts with each fill.
                        let fill = MPJourneyController.localPalette(journey.teamSeed).fill(i == 1 ? 0 : 1)
                        MPJourneyButton(title: role + ": " + (MPRoster.find(journey.ids[i]) ?? MPRoster.all[0]).name(hebrew: he),
                                        fill: MPColor.color(fill), textColor: MPColor.color(MPTeamColors.ink(fill))) { journey.picking = i }
                    }
                    MPJourneyButton(title: t("Start team match", "מתחילים במשחק קבוצתי"), face: MPCourtStyle.startFace) { journey.teamBrief = true }
                }
                .padding(.horizontal, 18).padding(.vertical, 16).frame(maxWidth: .infinity)
                .background(MPJourneyStyle.panel, in: RoundedRectangle(cornerRadius: 28))
                // Android: the two links sit beneath the panel.
                teamLink(t("How teams work", "איך משחקים בקבוצה")) { journey.teamBrief = false }
                teamLink(t("Online team game", "משחק קבוצתי ברשת")) { journey.openOnline() }
            }.frame(maxWidth: 620).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity)
        }
    }
    /// Android `ControlChoice.title` (29f5dc7 adds Starter = 1).
    static func controlTitle(_ value: Int, _ he: Bool) -> String {
        switch MPControlChoice.normalize(value) {
        case 1: return he ? "נינוחה" : "Starter"
        case 0: return he ? "רגילה" : "Standard"
        case 3: return he ? "מקצועני" : "Pro"
        default: return he ? "מתחילים" : "Beginner"
        }
    }
    private func teamLink(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .bold)).underline().foregroundStyle(MPJourneyStyle.link)
                .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
                .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    private var game: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
            if let g = journey.game {
                let court = MPPracticeCourt(game: g, hebrew: he, running: journey.running, soundsEnabled: { MPJourneyController.soundsOn }, onFrame: { journey.frame() }, scenery: scenery)
                ZStack {
                    if wide {
                        // Android PongCourtStyle.landscape: a full-height court with coaching in its start-side
                        // gutter; an equal empty gutter keeps the court centred. The court also draws into both
                        // gutters (`clipChildren = false`), so players who yield outward stay visible.
                        let side = min(max(proxy.size.width * 0.19, 144), 192)
                        court.withGutter(side)
                        HStack(spacing: 0) { MPJourneySidebar(journey: journey, game: g).frame(width: side); Spacer(minLength: 0) }
                    } else {
                        VStack(spacing: 6) { MPJourneyHud(journey: journey, game: g); court }
                    }
                    MPOrientationToast(hebrew: he)
                }
                .onAppear { MPOrientationHint.shared.observe(wide: wide); MPOrientationHint.shared.schedule(active: { journey.game?.ended == false && journey.page == .game }, wide: { wide }) }
                .onChange(of: wide) { _, value in MPOrientationHint.shared.observe(wide: value) }
            }
        }
        .padding(.horizontal, 6).padding(.bottom, 6)
        .background { if let g = journey.game, g.stage == nil, !g.openPaint { MPArenaBackdrop(arena: MPArena.read(g.arena), scenery: scenery) } }
    }
    private var result: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width > proxy.size.height && journey.game?.stage == nil
            MPJourneyPanel {
                if compact {
                    HStack(spacing: 8) {
                        if journey.resultWon, let g = journey.game { celebration(g).frame(width: 160, height: 130) }
                        VStack(spacing: 6) { winningCaption; text(journey.resultText, size: 20, bold: true) }
                    }
                    HStack(spacing: 12) { againButton; menuButton }.padding(.top, 12)
                } else {
                    if journey.resultWon, let g = journey.game { celebration(g).frame(height: g.team ? 250 : 170) }
                    winningCaption
                    text(journey.resultText, size: 20, bold: true)
                    againButton
                    menuButton.padding(.top, 14).padding(.bottom, 2)
                }
            }
        }
    }
    @ViewBuilder private func celebration(_ g: MPPlay) -> some View {
        if g.team { MPTeamVictory(characters: g.actors.filter { $0.team == 0 }.map(\.character), hebrew: he) }
        else { MPJourneyCelebration() }
    }
    /// Android `winning-team`: the winners' names on their team colour.
    @ViewBuilder private var winningCaption: some View {
        if let caption = journey.winningTeam, let g = journey.game {
            let fill = MPJourneyController.localPalette(g.seed).fill(journey.resultWinner)
            Text(caption).font(.system(size: 23, weight: .bold)).foregroundStyle(MPColor.color(MPTeamColors.ink(fill))).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(14)
                .background(MPColor.color(fill), in: RoundedRectangle(cornerRadius: 18))
                .padding(.vertical, 12)
        }
    }
    private var againButton: some View {
        MPJourneyButton(title: journey.resultAction, face: MPCourtStyle.startFace) { journey.resultPrimary() }
    }
    private var menuButton: some View {
        MPJourneyButton(title: t("Back to menu", "חזרה לתפריט"), fill: MPStyle.pink, textColor: .white) { journey.leave() }
    }
}

/// Android journey HUD (portrait): the score owns the full row; tools never shift its horizontal centre. A stage puts
/// the tools under the score; a team match keeps them at the end of the same row.
struct MPJourneyHud: View {
    @ObservedObject var journey: MPJourneyController
    let game: MPPlay
    var body: some View {
        VStack(spacing: 4) {
            if game.stage != nil {
                MPJourneyScore(journey: journey, game: game).frame(height: 48)
                MPJourneyTools(journey: journey, game: game)
            } else {
                ZStack {
                    MPJourneyScore(journey: journey, game: game).padding(.horizontal, 112)
                    HStack { Spacer(); MPJourneyTools(journey: journey, game: game) }
                }.frame(height: 48)
            }
            MPJourneyHint(journey: journey, lines: 3, size: 14)
        }.padding(.horizontal, 8).padding(.vertical, 6).background(MPJourneyStyle.hudBar, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Android landscape sidebar: tools above, then the outlined score and coaching (no filled panel).
struct MPJourneySidebar: View {
    @ObservedObject var journey: MPJourneyController
    let game: MPPlay
    var body: some View {
        VStack(spacing: 4) {
            MPJourneyTools(journey: journey, game: game).frame(height: 48)
            ScrollView {
                VStack(spacing: 14) {
                    MPJourneyScore(journey: journey, game: game, size: 24).shadow(color: MPColor.color(0xff071b3b), radius: 1.4)
                    MPJourneyHint(journey: journey, lines: 12, size: 15).shadow(color: MPColor.color(0xff071b3b), radius: 1.4)
                }.frame(maxWidth: .infinity).padding(.top, 4)
            }
            Color.clear.frame(height: 48)
        }.padding(.horizontal, 8).padding(.vertical, 4)
    }
}

struct MPJourneyScore: View {
    @ObservedObject var journey: MPJourneyController
    let game: MPPlay
    var size: CGFloat? = nil
    var body: some View {
        Group {
            if let colored = journey.hudScore { Text(colored) } else { Text(journey.hud).foregroundStyle(.white) }
        }
        .font(.system(size: size ?? (game.stage == nil ? 28 : 20), weight: .bold)).lineLimit(size == nil ? 1 : 4).minimumScaleFactor(0.6)
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(journey.hud).accessibilityAddTraits(.updatesFrequently)
    }
}

struct MPJourneyHint: View {
    @ObservedObject var journey: MPJourneyController
    let lines: Int
    let size: CGFloat
    var body: some View {
        Text(journey.hint).font(.system(size: size, weight: .bold)).foregroundStyle(.white)
            .multilineTextAlignment(journey.hintIsTip ? .leading : .center).lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: journey.hintIsTip ? .leading : .center).padding(.horizontal, 4).padding(.vertical, 5)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct MPJourneyTools: View {
    @ObservedObject var journey: MPJourneyController
    let game: MPPlay
    private func t(_ en: String, _ he: String) -> String { journey.tr(en, he) }
    var body: some View {
        HStack(spacing: 8) {
            Button { journey.togglePause() } label: {
                Image(systemName: game.paused ? "play.fill" : "pause.fill").font(.title3).foregroundStyle(MPJourneyStyle.ink).frame(width: 48, height: 48)
                    .background(MPJourneyStyle.cyan, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityLabel(game.paused ? t("Continue", "המשך") : t("Pause", "השהיה"))
            Button { journey.showInstructions(game) } label: {
                Image(systemName: "questionmark").font(.title3.bold()).foregroundStyle(MPJourneyStyle.ink).frame(width: 48, height: 48)
                    .background(MPJourneyStyle.cyan, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityLabel(t("Help", "עזרה"))
        }
    }
}

/// Android `PongInstructionDialog` (22f756e): title on a raised menu face, the scrollable explanation and a green
/// "Got it" button. It cannot be dismissed otherwise.
struct MPInstructionDialog: View {
    let title: String
    let message: String
    let hebrew: Bool
    let done: () -> Void
    var body: some View {
        GeometryReader { proxy in
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.center)
                        // Android c9f5fa6: the title is plain text, no longer on a raised menu face.
                        .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 16)
                    Text(message).font(.system(size: 18)).foregroundStyle(MPJourneyStyle.ink).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 18).padding(.bottom, 10)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: done) {
                        Text(hebrew ? "הבנתי" : "Got it").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(MPJourneyStyle.ink)
                            .frame(maxWidth: .infinity, minHeight: 56).background(MPCourtStyle.startFace.gradient, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).padding(.top, 14)
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 22)
                .background(MPColor.color(0xfff2faff), in: RoundedRectangle(cornerRadius: 26))
                .frame(maxWidth: 540).padding(.horizontal, 16).padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        }
        .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
        .accessibilityAddTraits(.isModal)
    }
}

/// Android `SettingSelector`-free settings page: sounds, menu music, ball assistance and grown-up links.
struct MPSettingsPage: View {
    @ObservedObject var journey: MPJourneyController
    @State private var assistanceOpen = false
    private func t(_ en: String, _ he: String) -> String { journey.tr(en, he) }
    var body: some View {
        MPJourneyPanel {
            Toggle(isOn: Binding(get: { MPJourneyController.soundsOn }, set: { journey.setSounds($0) })) {
                Text(t("Game sounds", "צלילי המשחק")).font(.system(size: 18, weight: .semibold)).foregroundStyle(MPJourneyStyle.ink)
            }.tint(MPStyle.pink).frame(minHeight: 56)
            Text(t("Paddle swings, ball contacts and celebrations in team games and daily practice.", "הנפות מחבט, פגיעות בכדור וחגיגות במשחקי קבוצה ובאימון היומי."))
                .font(.system(size: 14)).foregroundStyle(MPJourneyStyle.ink).frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: Binding(get: { MPJourneyController.musicOn }, set: { journey.setMusic($0) })) {
                Text(t("Menu music", "מוזיקה בתפריט")).font(.system(size: 17, weight: .semibold)).foregroundStyle(MPJourneyStyle.ink)
            }.tint(MPStyle.pink).frame(minHeight: 56)
            MPReceptionSettingsView(hebrew: journey.hebrew, open: $assistanceOpen)
            MPJourneyButton(title: t("Rate this app", "דירוג האפליקציה"), face: MPJourneyStyle.rateFace) { journey.gate = { journey.rateApp() } }
            MPJourneyButton(title: t("Share this app", "שיתוף האפליקציה"), face: MPJourneyStyle.shareFace) { journey.gate = { journey.shareApp() } }
            MPJourneyButton(title: t("Send feedback", "שליחת משוב"), face: MPJourneyStyle.feedbackFace) { journey.gate = { journey.sendFeedback() } }
        }
    }
}

/// Android `ReceptionSettings.add`: three choices, each explained, plus the shared note. All are off by default. The
/// toggle (29f5dc7) reads "+  Ball assistance" / "−  Ball assistance" on a pale blue raised face.
struct MPReceptionSettingsView: View {
    let hebrew: Bool
    @Binding var open: Bool
    @State private var values: [String: Bool] = Dictionary(uniqueKeysWithValues: MPReceptionSettings.keys.map { ($0, MPReceptionSettings.value($0)) })
    var body: some View {
        VStack(spacing: 8) {
            Button { open.toggle() } label: {
                Text((open ? "−  " : "+  ") + (hebrew ? "עזרה בקבלת הכדור" : "Ball assistance")).font(.system(size: 17, weight: .semibold)).foregroundStyle(MPJourneyStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 52).background(MPColor.color(0xffc4e5ff), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(MPReceptionSettings.keys, id: \.self) { key in
                        Toggle(isOn: Binding(get: { values[key] ?? false }, set: { values[key] = $0; MPReceptionSettings.set(key, $0) })) {
                            Text(MPReceptionSettings.title(key, hebrew: hebrew)).font(.system(size: 17)).foregroundStyle(MPJourneyStyle.ink)
                        }.tint(MPStyle.pink).frame(minHeight: 56)
                        Text(MPReceptionSettings.explanation(key, hebrew: hebrew)).font(.system(size: 14)).foregroundStyle(MPJourneyStyle.ink).padding(.bottom, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(MPReceptionSettings.note(hebrew: hebrew)).font(.system(size: 15)).foregroundStyle(MPJourneyStyle.ink).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }
}

/// Android `BotPicker`: one house player at a time with large arrows, its name and skills. The confirm button reads
/// "Select" unless the caller names it (29f5dc7).
struct MPHousePickerSheet: View {
    let hebrew: Bool
    @State var selected: String
    var excluded: Set<String> = []
    let confirm: String
    let picked: (String) -> Void
    let cancel: () -> Void
    init(hebrew: Bool, selected: String, excluded: Set<String> = [], confirm: String? = nil, picked: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.hebrew = hebrew; self.excluded = excluded; self.confirm = confirm ?? (hebrew ? "בחירה" : "Select"); self.picked = picked; self.cancel = cancel
        _selected = State(initialValue: selected)
    }
    var body: some View {
        VStack(spacing: 16) {
            Text(hebrew ? "שחקני הבית" : "House players").font(.title2.bold()).foregroundStyle(MPStyle.ink)
            MPHousePicker(hebrew: hebrew, selected: $selected, excluded: excluded)
            MPJourneyButton(title: confirm, accent: true) { picked(selected) }
            Button(hebrew ? "ביטול" : "Cancel", action: cancel).font(.headline).foregroundStyle(MPStyle.pink).frame(minHeight: 44)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.ignoresSafeArea())
            // A sheet is its own presentation: keep it light on Dark Mode devices, like the menu behind it.
            .preferredColorScheme(.light).presentationDetents([.medium, .large])
    }
}

/// Android `HousePlayerPicker`: arrows or a sideways swipe change the always-visible character.
struct MPHousePicker: View {
    let hebrew: Bool
    @Binding var selected: String
    var excluded: Set<String> = []
    var showSkills = true
    private var choices: [MPHousePlayer] { MPRoster.all.filter { !excluded.contains($0.id) } }
    private func move(_ step: Int) {
        let list = choices; guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selected } ?? 0
        withAnimation(.easeInOut(duration: 0.2)) { selected = list[(index + step + list.count) % list.count].id }
    }
    var body: some View {
        let player = choices.first { $0.id == selected } ?? choices.first ?? MPRoster.all[0]
        VStack(spacing: 10) {
            HStack {
                Button { move(-1) } label: { Text("‹").font(.system(size: 40, weight: .bold)).foregroundStyle(MPStyle.pink).frame(width: 54, height: 64) }
                    .accessibilityLabel(hebrew ? "השחקן הקודם" : "Previous player")
                MPAvatar(character: player.id, icon: 0).frame(maxWidth: .infinity).frame(height: 142).id(player.id)
                    .gesture(DragGesture(minimumDistance: 20).onEnded { if abs($0.translation.width) > abs($0.translation.height) { move($0.translation.width < 0 ? 1 : -1) } })
                Button { move(1) } label: { Text("›").font(.system(size: 40, weight: .bold)).foregroundStyle(MPStyle.pink).frame(width: 54, height: 64) }
                    .accessibilityLabel(hebrew ? "השחקן הבא" : "Next player")
            }.environment(\.layoutDirection, .leftToRight)
            Text(player.name(hebrew: hebrew)).font(.system(size: 22, weight: .bold)).foregroundStyle(MPStyle.ink)
            if showSkills {
                let p = player.profile
                Text(hebrew ? "עוצמה \(p.power)  •  כף יד \(p.forehandSkill)  •  גב יד \(p.backhandSkill)  •  הגשה \(p.serveSkill)" : "Power \(p.power)  •  Forehand \(p.forehandSkill)  •  Backhand \(p.backhandSkill)  •  Serve \(p.serveSkill)")
                    .font(.system(size: 14)).foregroundStyle(MPStyle.ink).multilineTextAlignment(.center)
            }
        }
        .onAppear { keepAvailable() }
        .onChange(of: excluded) { _, _ in keepAvailable() }
    }
    /// A character just added elsewhere is skipped, as Android rebuilds the picker without it.
    private func keepAvailable() {
        if !choices.contains(where: { $0.id == selected }), let first = choices.first { selected = first.id }
    }
}

/// Android `JourneyCelebration`: a finite ring of confetti around a check-mark badge; Reduce Motion shows it still.
struct MPJourneyCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var born = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(born), t = reduceMotion ? 1.8 : min(elapsed, 1.8)
                let cx = size.width / 2, cy = size.height / 2, r = size.height * 0.29
                let colors = [Color(red: 1, green: 0xd7 / 255, blue: 0x69 / 255), Color(red: 0x93 / 255, green: 0xf2 / 255, blue: 0xd2 / 255), Color(red: 0xc4 / 255, green: 0xb2 / 255, blue: 1), Color(red: 1, green: 0xb8 / 255, blue: 0xc9 / 255)]
                for i in 0..<20 {
                    let angle = Double(i) * 2 * .pi / 20, radius = r * (1.5 + CGFloat(min(t, 1)) * 0.85)
                    let x = cx + CGFloat(cos(angle)) * radius, y = cy + CGFloat(sin(angle)) * radius * 0.63
                    var piece = context
                    piece.translateBy(x: x, y: y); piece.rotate(by: .degrees(Double(i) * 31 + t * 75))
                    piece.fill(Path(roundedRect: CGRect(x: -4, y: -7, width: 8, height: 14), cornerRadius: 2), with: .color(colors[i % 4].opacity(elapsed < 1.8 && !reduceMotion ? 1 : 190.0 / 255)))
                }
                let ink = Color(red: 0x17 / 255, green: 0x3f / 255, blue: 0x55 / 255)
                context.fill(Path(ellipseIn: CGRect(x: cx - r * 1.12, y: cy - r * 1.12, width: r * 2.24, height: r * 2.24)), with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(colors[0]))
                var tick = Path(); tick.move(to: CGPoint(x: cx - r * 0.43, y: cy)); tick.addLine(to: CGPoint(x: cx - r * 0.08, y: cy + r * 0.29)); tick.addLine(to: CGPoint(x: cx + r * 0.47, y: cy - r * 0.3))
                context.stroke(tick, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}

/// Android `TeamVictoryView`: the two selected teammates jump together, then stay as a team portrait.
struct MPTeamVictory: View {
    let characters: [String]
    let hebrew: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var born = Date()
    private var art: [UIImage] {
        var seen: [String] = []
        for id in characters where !seen.contains(id) { seen.append(id) }
        return seen.prefix(2).compactMap { MPArtFiles.image("team-celebration/" + $0 + ".webp") }
    }
    var body: some View {
        let images = art
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let seconds = timeline.date.timeIntervalSince(born)
                let hop: Double = !reduceMotion && seconds < 2.4 ? max(0, sin(seconds * Double.pi / 0.8)) : 0
                let jump = CGFloat(hop) * size.height * 0.12
                let colors = [Color(red: 1, green: 0xd7 / 255, blue: 0x6a / 255), Color(red: 0xb7 / 255, green: 0x35 / 255, blue: 0x78 / 255), Color(red: 0x36 / 255, green: 0x8d / 255, blue: 0xec / 255), Color(red: 0x4f / 255, green: 0xca / 255, blue: 0xa3 / 255)]
                for i in 0..<36 {
                    let x = size.width * CGFloat(i * 37 % 101) / 101, y = size.height * CGFloat(i * 23 % 103) / 103
                    var piece = context
                    piece.translateBy(x: x, y: y); piece.rotate(by: .degrees(Double(i) * 31))
                    piece.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 5, height: 10), cornerRadius: 2), with: .color(colors[i % 4].opacity(190.0 / 255)))
                }
                for (i, image) in images.enumerated() {
                    let maxH = size.height * 0.79, maxW = size.width / (CGFloat(images.count) + 0.35)
                    let s = min(maxH / max(image.size.height, 1), maxW / max(image.size.width, 1)), w = image.size.width * s, h = image.size.height * s
                    let place: CGFloat = images.count == 1 ? 0.5 : i == 0 ? 0.32 : 0.68
                    let cx = size.width * place, bottom = size.height * 0.96 - jump
                    context.fill(Path(ellipseIn: CGRect(x: cx - w * 0.27, y: size.height * 0.94, width: w * 0.54, height: size.height * 0.04)), with: .color(Color(red: 0x13 / 255, green: 0x29 / 255, blue: 0x26 / 255).opacity(0x28 / 255)))
                    context.draw(Image(uiImage: image), in: CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h))
                }
            }
        }.accessibilityLabel(hebrew ? "חברי הקבוצה חוגגים יחד" : "Your teammates celebrate together")
    }
}
