import SwiftUI
import Combine
import StoreKit
import UIKit

/// Android `PongJourneyActivity`: the daily skill journey, local team play, the settings page and the online team
/// entry. No ads run here, as on Android.
@MainActor final class MPJourneyController: ObservableObject {
    enum Page { case brief, list, teams, game, result, settings, online }
    @Published private(set) var page = Page.brief
    @Published private(set) var game: MPPlay?
    @Published var mode = MPTeamMode.alternate
    @Published var ids = ["miniko", "minik", "mia", "june"]
    @Published private(set) var hud = ""
    @Published private(set) var hint = ""
    @Published private(set) var running = false
    @Published var instructions: MPPlay?
    /// Team rules dialog: true starts a match, false practises the skill.
    @Published var teamBrief: Bool?
    @Published var picking: Int?
    @Published var notice: String?
    @Published var gate: (() -> Void)?
    @Published var share: MPShareItem?
    @Published private(set) var online: MPOnlineTeamsController?
    @Published private(set) var resultWon = false
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

    func open(_ page: Page, identity: MPIdentity?, hebrew: Bool) {
        self.identity = identity; self.hebrew = hebrew
        // Android: the player's avatar first, then the roster order.
        let avatar = MPRoster.find(identity?.characterId ?? "")?.id ?? "miniko"
        ids = Array(([avatar] + MPRoster.all.map(\.id).filter { $0 != avatar }).prefix(4))
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
    func back() {
        switch page {
        case .game:
            let wasTeam = game?.stage == nil
            save(); game = nil; running = false
            if wasTeam { teamSetup() } else { brief() }
        case .online: online?.back()
        default: leave()
        }
    }
    func leave() {
        save(); online?.close(); online = nil; game = nil; running = false; resultAudio.stop()
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
        for _ in 0..<3 { let b = s.partner(step / 30, exclude: used); used.insert(b.id); roster.append(b.id) }
        let g = MPPlay(step: step, roster: roster)
        play(g); showInstructions(g)
    }
    func play(_ g: MPPlay) {
        game = g; page = .game; handled = false; hud = ""; hint = ""
        running = resumed && !g.paused
        frame()
    }
    func startTeam() { play(MPPlay(mode: mode, roster: ids)) }
    func practiseTeamSkill() { startJourney(mode == .alternate ? 15 : 16) }
    /// Android `teamBrief`: the stage's team briefing plus the match rule.
    var teamBriefing: String {
        MPJourney.stages[mode == .alternate ? 15 : 16].briefing(hebrew) + "\n\n" + tr("Drag to move. Tap a far-side target to return. First team to 7 points wins.", "גררו כדי לזוז. הקישו על יעד בצד הרחוק כדי להחזיר. הקבוצה הראשונה שתגיע ל־7 נקודות מנצחת.")
    }
    /// Each place needs a different character (Android shows a short notice).
    func choose(_ index: Int, _ id: String) {
        if ids.enumerated().contains(where: { $0.offset != index && $0.element == id }) {
            notice = tr("Choose a different character for each place", "בחרו דמות אחרת לכל מקום")
        } else { ids[index] = id }
    }
    func showInstructions(_ g: MPPlay) { g.paused = true; running = false; instructions = g; frame() }
    func closeInstructions() {
        instructions?.paused = false; instructions = nil
        running = resumed && page == .game && game?.paused == false; frame()
    }
    func togglePause() {
        guard let g = game else { return }
        g.paused.toggle(); running = !g.paused && resumed; frame()
    }
    func instructionsTitle(_ g: MPPlay) -> String { g.stage.map { $0.title(hebrew) } ?? tr("Team match", "משחק קבוצתי") }
    func instructionsText(_ g: MPPlay) -> String { g.stage?.briefing(hebrew) ?? MPJourney.stages[g.alternate ? 15 : 16].briefing(hebrew) }
    /// Android `refresh`: the score line, the advice line and the end of a challenge.
    func frame() {
        guard let g = game, page == .game else { return }
        let score: String
        if g.stage?.territory == true { score = "\(Int(g.remaining))s · \(Int(g.paint.coverage(0) * 100))% : \(Int(g.paint.coverage(1) * 100))%" }
        else if g.stage == nil { score = "\(g.points[0]) : \(g.points[1])" }
        else if g.openPaint { score = "★ \(g.successes)" }
        else { score = "\(g.successes) / \(g.goal)  · " + tr("Misses", "החטאות") + " \(g.mistakes)/3" }
        if hud != score { hud = score }
        let advice: String
        if g.paused { advice = tr("Paused", "מושהה") }
        else if let ending = g.ending { advice = ending.message(hebrew) }
        else if g.stage?.skill == .serve { advice = tr("Land the serve inside the golden island", "הנחיתו את ההגשה בתוך האי הזהוב") }
        else if g.waitingServe { advice = tr("Tap the far side to serve", "הקישו בצד הרחוק כדי להגיש") }
        else if g.team && g.alternate && g.nextHitter[0] != 0 { advice = tr("Your teammate's turn. Cover your side.", "תור חבר הקבוצה. שמרו על הצד שלכם.") }
        else if g.targeted { advice = tr("Drag toward the ball, then tap the golden target", "גררו לכדור, ואז הקישו על היעד הזהוב") }
        else { advice = tr("Drag to move. Tap the far side to return.", "גררו כדי לזוז. הקישו בצד הרחוק להחזרה.") }
        if hint != advice { hint = advice }
        if g.ended && g.ending == nil && !handled {
            handled = true; running = false
            Task { @MainActor [weak self] in self?.result(g) }
        }
    }
    @Published private(set) var resultText = ""
    private func result(_ g: MPPlay) {
        guard game === g else { return }
        page = .result; resultWon = g.won
        defaults.removeObject(forKey: MPJourneyController.prefix + "saved")
        let p = MPJourneyController.prefix
        if g.won, let stage = g.stage, g.step == step {
            let receipt = "\(g.step / 30)/" + stage.id
            var receipts = Set(defaults.stringArray(forKey: p + "receipts") ?? [])
            if receipts.insert(receipt).inserted {
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                let bonus = defaults.string(forKey: p + "day") != today ? 30 : 0
                defaults.set(Array(receipts), forKey: p + "receipts"); defaults.set(today, forKey: p + "day")
                defaults.set(stars + 40 + g.cycle * 10 + bonus, forKey: p + "stars"); defaults.set(g.step + 1, forKey: p + "step")
            }
        }
        if g.won && MPJourneyController.soundsOn { resultAudio.play("minik_claps") }
        if g.stage == nil { resultText = tr("Final score: \(g.points[0]) : \(g.points[1])", "התוצאה: \(g.points[0]) : \(g.points[1])") }
        else if g.won { resultText = tr("Nice work. Your next skill is ready.", "כל הכבוד. המיומנות הבאה מחכה לכם.") }
        else { resultText = tr("Your progress is safe. Take your time and try again.", "ההתקדמות שלכם נשמרת. קחו את הזמן ונסו שוב.") }
    }
    var resultAction: String {
        guard let g = game else { return "" }
        if g.stage == nil { return tr("Play again", "משחק נוסף") }
        return g.won ? tr("Next briefing", "הסבר לאתגר הבא") : tr("Try again", "מנסים שוב")
    }
    func resultPrimary() {
        guard let g = game else { brief(); return }
        if g.stage == nil { teamSetup() } else if g.won { brief() } else if g.step >= 0 { startJourney(g.step) } else { teamSetup() }
    }
    func openOnline() {
        let controller = MPOnlineTeamsController(mode: mode, identity: MPTeamIdentity.local(identity, hebrew: hebrew), hebrew: hebrew)
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
}

struct MPJourneyButton: View {
    let title: String
    var accent = false
    var fill: Color? = nil
    var textColor = MPJourneyStyle.ink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(textColor).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 14)
                .background(fill ?? (accent ? MPJourneyStyle.gold : MPJourneyStyle.cyan), in: RoundedRectangle(cornerRadius: 22))
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

struct MPJourneyScreen: View {
    @ObservedObject var journey: MPJourneyController
    private var he: Bool { journey.hebrew }
    private func t(_ en: String, _ he: String) -> String { journey.tr(en, he) }
    private func text(_ value: String, size: CGFloat = 17, bold: Bool = false) -> some View {
        Text(value).font(.system(size: size, weight: bold ? .bold : .regular)).foregroundStyle(MPJourneyStyle.ink)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 6).fixedSize(horizontal: false, vertical: true)
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
        .alert(journey.instructions.map { journey.instructionsTitle($0) } ?? "", isPresented: Binding(get: { journey.instructions != nil }, set: { if !$0 && journey.instructions != nil { journey.closeInstructions() } })) {
            Button(t("Got it · Play", "הבנתי · מתחילים")) { journey.closeInstructions() }
        } message: { Text(journey.instructions.map { journey.instructionsText($0) } ?? "") }
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
                MPHousePickerSheet(hebrew: he, selected: journey.ids[index], confirm: t("Play", "לשחק"), picked: { id in journey.choose(index, id); journey.picking = nil },
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
    private var brief: some View {
        let n = journey.step, s = MPJourney.stage(n), partner = s.partner(n / 30, exclude: [journey.ids[0]])
        return MPJourneyPanel {
            text(t("Practice a little each day. Your first completed stage each day earns a bonus. Play more whenever you like; missing a day never erases progress.", "מתאמנים קצת בכל יום. השלב הראשון שתשלימו ביום מזכה בבונוס. אפשר להמשיך לשחק מתי שרוצים; יום ללא משחק אינו מוחק התקדמות."), size: 15)
            text("\(n % 30 + 1) / 30 · " + t("Cycle", "מסלול") + " \(n / 30 + 1)", size: 18, bold: true)
            text(s.title(he), size: 24, bold: true)
            MPAvatar(character: partner.id, icon: 0).frame(height: 130).accessibilityLabel(partner.name(hebrew: he))
            text(partner.name(hebrew: he), size: 19, bold: true)
            text(s.role(he), size: 15)
            text(s.briefing(he))
            text(s.territory ? t("90 seconds · Capture more area to win", "90 שניות · כובשים יותר שטח כדי לנצח") : t("Goal: \(s.goal(n / 30)) · 3 misses before a retry", "מטרה: \(s.goal(n / 30)) · אחרי 3 החטאות מנסים שוב"), bold: true)
            if s.streak { text(t("Keep a streak: a miss resets the counter.", "שומרים על רצף: החטאה מאפסת את המונה."), size: 15) }
            MPJourneyButton(title: t("Start challenge", "מתחילים באתגר"), accent: true) { journey.startJourney(n) }
            if journey.hasSaved { MPJourneyButton(title: t("Resume practice", "המשך אימון")) { journey.resume() } }
            MPJourneyButton(title: t("Your journey", "המסע שלכם")) { journey.journeyList() }
            MPJourneyButton(title: t("Paint playground · no limit", "מגרש הצבעים · בלי הגבלה")) { journey.paintPlayground() }
            text(t("Practice stars", "כוכבי אימון") + ": \(journey.stars)", size: 15)
        }
    }
    private var list: some View {
        let n = journey.step % 30
        return MPJourneyPanel {
            ForEach(MPJourney.stages.indices, id: \.self) { i in
                text((i < n ? "✓" : i == n ? "★" : "○") + " \(i + 1). " + MPJourney.stages[i].title(he))
            }
            MPJourneyButton(title: t("Back to your challenge", "חזרה לאתגר שלכם")) { journey.brief() }
        }
    }
    private var teams: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    text(t("You and a house teammate against two house players", "אתם וחבר קבוצתכם מול שני שחקני בית"), size: 18, bold: true)
                    text(t("Team rules", "חוקי הקבוצה"), size: 16, bold: true)
                    MPChoiceBar(title: t("Team rules", "חוקי הקבוצה"), options: MPTeamMode.allCases.map { (value: $0, label: $0.title(he)) }, selection: $journey.mode)
                    text(journey.mode.explanation(he), size: 16)
                    ForEach(1..<4, id: \.self) { i in
                        let role = i == 1 ? t("Your teammate", "חבר הקבוצה שלכם") : t("Opponent", "יריב") + " \(i - 1)"
                        MPJourneyButton(title: role + ": " + (MPRoster.find(journey.ids[i]) ?? MPRoster.all[0]).name(hebrew: he)) { journey.picking = i }
                    }
                    MPJourneyButton(title: t("Start team match", "מתחילים במשחק קבוצתי"), accent: true) { journey.teamBrief = true }
                }
                .padding(.horizontal, 18).padding(.vertical, 16).frame(maxWidth: .infinity)
                .background(MPJourneyStyle.panel, in: RoundedRectangle(cornerRadius: 28))
                // Android: the two links sit beneath the panel.
                teamLink(t("How teams work", "איך משחקים בקבוצה")) { journey.teamBrief = false }
                teamLink(t("Online team game", "משחק קבוצתי ברשת")) { journey.openOnline() }
            }.frame(maxWidth: 620).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity)
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
                let court = MPPracticeCourt(game: g, hebrew: he, running: journey.running, soundsEnabled: { MPJourneyController.soundsOn }, onFrame: { journey.frame() })
                if wide {
                    HStack(spacing: 8) { ScrollView { controls(g) }.frame(width: 204); court }
                } else {
                    VStack(spacing: 6) { controls(g); court }
                }
            }
        }.padding(.horizontal, 6).padding(.bottom, 6)
    }
    private func controls(_ g: MPPlay) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(journey.hud).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity).environment(\.layoutDirection, .leftToRight)
                Button { journey.togglePause() } label: {
                    Image(systemName: g.paused ? "play.fill" : "pause.fill").font(.title3).foregroundStyle(MPJourneyStyle.ink).frame(width: 48, height: 48)
                        .background(MPJourneyStyle.cyan, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityLabel(g.paused ? t("Continue", "המשך") : t("Pause", "השהיה"))
                Button { journey.showInstructions(g) } label: {
                    Image(systemName: "questionmark").font(.title3.bold()).foregroundStyle(MPJourneyStyle.ink).frame(width: 48, height: 48)
                        .background(MPJourneyStyle.cyan, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityLabel(t("Help", "עזרה"))
            }
            Text(journey.hint).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(3)
                .frame(maxWidth: .infinity).padding(.horizontal, 4).padding(.vertical, 5)
                .accessibilityAddTraits(.updatesFrequently)
        }.padding(.horizontal, 8).padding(.vertical, 6).background(MPJourneyStyle.hudBar, in: RoundedRectangle(cornerRadius: 18))
    }
    private var result: some View {
        MPJourneyPanel {
            if journey.resultWon, let g = journey.game {
                if g.team { MPTeamVictory(characters: g.actors.filter { $0.team == 0 }.map(\.character), hebrew: he).frame(height: 250) }
                else { MPJourneyCelebration().frame(height: 170) }
            }
            text(journey.resultText, size: 20, bold: true)
            MPJourneyButton(title: journey.resultAction, accent: true) { journey.resultPrimary() }
            MPJourneyButton(title: t("Back to menu", "חזרה לתפריט")) { journey.leave() }
        }
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
            MPJourneyButton(title: t("Rate this app", "דירוג האפליקציה")) { journey.gate = { journey.rateApp() } }
            MPJourneyButton(title: t("Share this app", "שיתוף האפליקציה")) { journey.gate = { journey.shareApp() } }
            MPJourneyButton(title: t("Send feedback", "שליחת משוב")) { journey.gate = { journey.sendFeedback() } }
        }
    }
}

/// Android `ReceptionSettings.add`: three choices, each explained, plus the shared note. All are off by default.
struct MPReceptionSettingsView: View {
    let hebrew: Bool
    @Binding var open: Bool
    @State private var values: [String: Bool] = Dictionary(uniqueKeysWithValues: MPReceptionSettings.keys.map { ($0, MPReceptionSettings.value($0)) })
    var body: some View {
        VStack(spacing: 8) {
            Button { open.toggle() } label: {
                Text(MPReceptionSettings.title(hebrew: hebrew)).font(.system(size: 17, weight: .semibold)).foregroundStyle(MPJourneyStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 52).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
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

/// Android `BotPicker`: one house player at a time with large arrows, its name and skills.
struct MPHousePickerSheet: View {
    let hebrew: Bool
    @State var selected: String
    var excluded: Set<String> = []
    let confirm: String
    let picked: (String) -> Void
    let cancel: () -> Void
    init(hebrew: Bool, selected: String, excluded: Set<String> = [], confirm: String, picked: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.hebrew = hebrew; self.excluded = excluded; self.confirm = confirm; self.picked = picked; self.cancel = cancel
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
