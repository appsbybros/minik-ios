import SwiftUI
import SpriteKit
import StoreKit

/// Reusable Modern entry point. Simple never initializes Firebase or exposes its menus/help.
/// Simple reports each completed match once with onClose(result), then shows its result screen; leaving the
/// game calls onClose(nil), and only then does the host dismiss its presentation.
@MainActor struct ModernPongView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @StateObject private var model: MPController
    @StateObject private var commerce: MinikCommerceController
    @State private var expanded: Set<String> = []
    @State private var joinCode = ""
    @State private var nicknameIndex = 0
    @State private var avatarIndex = 0
    @State private var avatarCharacter = "miniko"
    @State private var capacity = 4
    @State private var legs = 1
    @State private var winPoints = 3
    /// Android PlayActivity: a knockout has its own player selector (2…9, default 8).
    @State private var knockoutCapacity = 8
    @State private var tournamentFormat = MPTournamentFormat.roundRobin
    @State private var carouselDirection = 1
    @State private var redeem = false
    @State private var showHelp = false
    @State private var showCommerce = false
    /// Purchase, restore and code redemption are reachable only after the grown-up gate (Android MonetizationActivity).
    @State private var commerceUnlocked = false
    @State private var copied = false
    @State private var showGameSettings = false
    @State private var receptionOpen = false
    /// Android PlayActivity.tournamentExitButton: Delete / Leave asks first.
    @State private var confirmExit = false
    @State private var friendlyCode = ""
    /// Android HousePlayerPicker in a tournament's waiting room: stays on screen until the roster is full.
    @State private var houseChoice = "minik"
    @State private var tournamentCode = ""
    /// Android PongRankDialog.
    @State private var showRank = false
    /// Android landscape match layout (PongCourtStyle.landscape): the screen is wider than tall.
    @State private var wide = false
    /// Android `PongHelpTips.next` on the guide's first lesson card ("Did you know?"), counted once per showing.
    @State private var guideTip = ""
    /// Android PongOrientationHint toast.
    @State private var landscapeTip = false
    private let gap: CGFloat = 12
    init(experience: ModernPongExperience = .full, commerce: MinikCommerceController? = nil, onClose: @escaping (ModernPongResult?) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: MPController(experience: experience, onClose: onClose))
        _commerce = StateObject(wrappedValue: commerce ?? MinikCommerceComposition.makeController(product: .current))
    }
    private var he: Bool { locale.language.languageCode?.identifier == "he" }
    private func t(_ en: String, _ he: String) -> String { self.he ? he : en }
    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: he ? "arrow.right" : "arrow.left")
                .font(.system(size: 27, weight: .heavy)).frame(width: 48, height: 48)
        }.foregroundStyle(MPStyle.pink).accessibilityLabel(t("Back", "חזרה"))
    }
    /// Android PongCourtStyle.landscape: a match in landscape moves its tools, score and coaching into a side gutter.
    private var landscapeGame: Bool { wide && model.route == .game && !model.loading }
    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if !landscapeGame { header }
                if model.loading { loadingPage }
                else {
                    switch model.route {
                    case .menu: menu
                    case .lobby: lobby
                    case .game: game
                    case .guide: guide
                    case .result: result
                    case .journey: MPJourneyScreen(journey: model.journey)
                    case .createTournament: createTournamentPage
                    case .createFriendly: createFriendlyPage
                    case .colorChallenge: MPColorChallengeView(model: model, hebrew: he)
                    }
                }
            }
        }
        .background { GeometryReader { proxy in Color.clear.onAppear { wide = proxy.size.width > proxy.size.height }.onChange(of: proxy.size) { _, size in wide = size.width > size.height } }.ignoresSafeArea() }
        .overlay {
            // Android VictoryConfetti: brief and noninteractive; a new celebration restarts it.
            if let celebration = model.celebration { MPVictoryConfetti().id(celebration) }
        }
        .overlay {
            // Android ColorChallengeActivity.celebrate: the colour just earned, over the menu or the challenge screen.
            if let level = model.promotion {
                MPRankCelebration(level: level, character: MPRoster.find(model.identity?.characterId ?? "miniko")?.id ?? "minik", hebrew: he) { model.promotion = nil }
            }
        }
        .foregroundStyle(MPStyle.ink).preferredColorScheme(.light)
        .environment(\.layoutDirection, he ? .rightToLeft : .leftToRight)
        .task {
            await commerce.start(); await model.start(hebrew: he, removeAds: commerce.isRemoveAdsActive)
            if model.experience == .full { model.applyStoreScreenshotScene() }
        }
        .onChange(of: he) { _, value in model.hebrew = value }
        .onChange(of: phase) { _, value in model.lifecycle(active: value == .active) }
        .onChange(of: commerce.isRemoveAdsActive) { _, value in model.ads.removeAds(value) }
        .onDisappear { model.close() }
        .task(id: model.route) { await familyMenuIdle() }
        .alert(model.errorTitle ?? t("Please try again", "נסו שוב"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil; model.errorTitle = nil } })) {
            Button(t("OK", "אישור")) { model.error = nil; model.errorTitle = nil }
        } message: { Text(model.error ?? "") }
        .alert(t("Save this tournament?", "לשמור את הטורניר?"), isPresented: $model.tournamentExitPrompt) {
            Button(t("Save", "שמירה")) { model.saveTournamentAndLeave() }
            Button(t("Don't save", "לא לשמור"), role: .destructive) { Task { await model.discardTournament() } }
            Button(t("Cancel", "ביטול"), role: .cancel) { model.tournamentExitPrompt = false }
        } message: { Text(tournamentExitMessage) }
        .alert(exitTitle, isPresented: $confirmExit) {
            Button(t("Cancel", "ביטול"), role: .cancel) {}
            Button(exitDeletes ? t("Delete", "מחיקה") : t("Leave", "עזיבה"), role: .destructive) { Task { await model.leave(delete: exitDeletes) } }
        } message: { Text(exitDeletes ? t("The tournament and its matches will be deleted for everyone.", "הטורניר והמשחקים שלו יימחקו עבור כולם.") : t("Your completed results stay. Your unfinished matches are cancelled.", "התוצאות שהושלמו נשמרות. המשחקים שלכם שטרם הסתיימו מבוטלים.")) }
        .sheet(isPresented: $showHelp) { help }
        .sheet(isPresented: $showRank) { MPRankSheet(ranking: model.ranking, hebrew: he) { showRank = false } }
        .sheet(isPresented: $showCommerce, onDismiss: { commerceUnlocked = false }) {
            if commerceUnlocked { commerceSheet }
            else { ParentalGateView(onCancel: { showCommerce = false }, onUnlock: { commerceUnlocked = true }) }
        }
        .sheet(isPresented: $showGameSettings, onDismiss: { if model.paused { model.togglePause() } }) { gameSettings }
        .offerCodeRedemption(isPresented: $redeem) { _ in Task { await commerce.refreshEntitlements() } }
    }
    private var caption: String {
        switch model.route {
        case .menu: return "MINIK Ping Pong"
        case .lobby: return model.session?.kind == .tournament ? t("Tournament", "טורניר") : t("Friendly game", "משחק ידידות")
        case .game: return model.session?.kind == .tournament ? t("Tournament match", "משחק בטורניר") : t("Ping Pong", "פינג פונג")
        case .guide: return t("Learn with Minik", "לומדים עם מיניק")
        case .result: return t("Match result", "תוצאת המשחק")
        case .journey: return model.journey.title
        case .createTournament: return t("Create tournament", "יצירת טורניר")
        case .createFriendly: return t("New friendly game", "משחק ידידות חדש")
        case .colorChallenge: return t("Color Challenge", "אתגר הצבע")
        }
    }
    /// Android LocalizedActivity.safeContent(arena:): a match is played in its arena's scenery; menus keep the
    /// original illustrated setting.
    @ViewBuilder private var pageBackground: some View {
        if model.route == .game, let arena = model.scene?.selectedArena, MPArenaPageBackdrop.available(arena) { MPArenaPageBackdrop(arena: arena) }
        else { MPIllustratedBackground() }
    }
    /// Android PlayActivity.showMatchLoading and PrivateMatchActivity's first screen.
    private var loadingPage: some View {
        VStack(spacing: 24) {
            Text(t("Loading…", "טוענים…")).font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
            ProgressView().tint(.white).scaleEffect(1.4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var exitDeletes: Bool { model.session.map { MPRules.canDelete($0, actor: model.userID) } ?? false }
    private var exitTitle: String { exitDeletes ? t("Delete tournament?", "למחוק את הטורניר?") : t("Leave tournament?", "לעזוב את הטורניר?") }
    private var tournamentExitMessage: String {
        exitDeletes ? t("Save to continue later. Don't save deletes this tournament and its matches.", "שמרו כדי להמשיך מאוחר יותר. ללא שמירה, הטורניר והמשחקים שלו יימחקו.")
            : t("Save to continue later. Don't save leaves the tournament; other players can continue.", "שמרו כדי להמשיך מאוחר יותר. ללא שמירה, תעזבו את הטורניר והשחקנים האחרים יוכלו להמשיך.")
    }
    private var header: some View {
        ZStack {
            Text(caption).font(.system(.title2, design: .rounded, weight: .bold)).multilineTextAlignment(.center).padding(.horizontal, 58)
            HStack {
                if model.route != .menu || model.experience == .simple {
                    backButton { model.back() }
                }
                Spacer()
                if model.route == .menu { Button { showHelp = true } label: { Image(systemName: "questionmark.circle.fill").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel(t("Help", "עזרה")) }
                else if model.route == .game { Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel(model.paused ? t("Resume", "המשך") : t("Pause", "השהיה")) }
            }
        }.frame(minHeight: 60).padding(.horizontal, 8)
        // Android ModernActivity's screen bar: white text on a dark rounded bar, readable over the artwork.
        .foregroundStyle(.white)
        .background(MPStyle.bar, in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 8).padding(.top, 4)
    }
    private var menu: some View {
        ScrollView {
            VStack(spacing: gap) {
                Image("mp_app_icon").resizable().scaledToFit().frame(maxWidth: 220, maxHeight: 220).accessibilityHidden(true).padding(.bottom, 16)
                if model.experience.profiles {
                    // Android PlayActivity.home (2026-10): four sections; the first two start open and each section
                    // remembers its choice.
                    MPMenuSection(id: "learn", title: t("Start & learn", "מתחילים ולומדים"), openByDefault: true) {
                        // Android PlayActivity.home (6feaac5): the colour-rank summary opens the colour explanation.
                        let _ = model.rankRevision
                        MPRankSummary(ranking: model.ranking, hebrew: he) { showRank = true }
                        sectionButton(t("Learn how to play with Mega Minik", "לומדים לשחק עם מגה מיניק"), MPStyle.blue) { model.guide() }
                        sectionButton(t("Daily skill journey", "אתגר יומי"), MPStyle.blue) { model.openJourney(.brief) }
                        // Shown once the points for the next colour are earned, in that colour.
                        if let next = model.ranking.state.next, model.ranking.state.eligible { colorChallengeButton(MPRanks.all[next]) }
                        sectionButton((expanded.contains("profile") ? "−  " : "+  ") + t("Nickname & avatar", "כינוי ודמות") + " · " + (model.identity?.name ?? MPNames.candidate(0, hebrew: he, character: "miniko")), MPStyle.blue) {
                            if !expanded.contains("profile") { avatarIndex = model.identity?.avatar ?? 0; avatarCharacter = model.identity?.characterId ?? "miniko" }
                            toggle("profile")
                        }.accessibilityLabel(t("Choose your nickname and avatar", "בחירת כינוי ודמות"))
                        if expanded.contains("profile") { profileEditor }
                    }
                    MPMenuSection(id: "play", title: t("Play", "משחקים"), openByDefault: true) {
                        // Android PlayActivity (305914e): the friendly setup is its own page.
                        sectionButton(t("New friendly game", "משחק ידידות חדש"), MPStyle.mint) { model.openFriendlyOptions() }
                        sectionButton(t("Play as a team", "משחק קבוצתי"), MPStyle.mint) { model.openJourney(.teams) }
                        sectionButton(t("New tournament", "טורניר חדש"), MPStyle.mint) { toggle("tournament") }
                        if expanded.contains("tournament") { tournamentEntry }
                        if model.online {
                            if model.connecting { ProgressView(t("Connecting…", "מתחברים…")).tint(.white).foregroundStyle(.white) }
                            else if !model.connected {
                                // Starting offline shows this note instead of a dialog (owner report 2026-10).
                                Text(t("Online play isn't available right now. You can still play with the house players.", "המשחק המקוון אינו זמין כרגע. אפשר לשחק עם שחקני הבית.")).font(.callout).foregroundStyle(.white).multilineTextAlignment(.center)
                                Button(t("Retry online connection", "נסו להתחבר שוב")) { Task { await model.retryOnline(removeAds: commerce.isRemoveAdsActive) } }.font(.headline).foregroundStyle(MPStyle.link).padding(12)
                            }
                        }
                    }
                    MPMenuSection(id: "saved", title: t("Saved games", "משחקים שמורים"), openByDefault: false) {
                        roomSection(.friendly)
                        roomSection(.tournament)
                    }
                    MPMenuSection(id: "advanced", title: t("Advanced", "מתקדם"), openByDefault: false) {
                        sectionButton(t("Settings · Feedback & sharing", "הגדרות · משוב ושיתוף"), MPStyle.yellow) { model.openJourney(.settings) }
                        // Android PlayActivity (Advanced): "More Minik apps & games" as a link, behind the family grown-up gate.
                        familyLink(FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק")) { FamilyMessages.shared.showMoreApps(gate: nil) }
                    }
                    // Android PlayActivity (2026-10): the parents' link is dark blue below the sections.
                    familyLink(commerce.isRemoveAdsActive ? t("Parents / adults · Ads removed", "להורים ולמבוגרים · הפרסומות הוסרו") : t("Parents / adults · Remove ads", "להורים ולמבוגרים · הסרת פרסומות"), color: MPColor.color(0xff205ca8)) { commerceUnlocked = false; showCommerce = true }
                } else {
                    action(t("Learn how to play with Mega Minik", "לומדים לשחק עם מגה מיניק"), color: MPStyle.mint) { model.guide() }
                    controls
                    carousel
                    action(t("Start", "התחלת משחק"), color: MPStyle.blue) { model.startSingle() }
                }
                if model.busy { ProgressView().accessibilityLabel(t("Loading", "טוען")) }
            }.frame(maxWidth: 680).padding(.horizontal, 16).padding(.bottom, 28).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
    }
    /// A menu action in its section's colour (Android `FamilyMenu.style`): ink text, 64 points high.
    private func sectionButton(_ title: String, _ color: Color, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(MPStyle.ink).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 64).padding(.horizontal, 12)
        }.buttonStyle(.plain).background(color, in: RoundedRectangle(cornerRadius: 15)).padding(.vertical, 2).disabled(model.busy)
    }
    /// Android PlayActivity.home: "Color Challenge" on the next colour's raised face, in that colour's ink.
    private func colorChallengeButton(_ next: MPRank) -> some View {
        Button { model.openColorChallenge() } label: {
            Text(t("Color Challenge", "אתגר הצבע")).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(MPColor.color(next.ink)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 64).padding(.horizontal, 12)
                .background(MPRankPresentation.background(next, radius: 18))
        }.buttonStyle(.plain).padding(.vertical, 2).disabled(model.busy)
    }
    /// Android PlayActivity: "New tournament" offers only Create room and joining with a code.
    private var tournamentEntry: some View {
        card {
            action(t("Create room", "יצירת חדר"), color: MPStyle.blue) { model.openTournamentOptions() }.disabled(!model.connected)
            MPDashedDivider()
            joinForm(code: $tournamentCode, label: t("Room code", "קוד חדר"), button: t("Join room", "הצטרפות לחדר"))
        }
    }
    /// `requireValid`: Android's friendly "Join with a code" stays dimmed until the six characters form a code (f0f27c4).
    private func joinForm(code: Binding<String>, label: String, button: String, requireValid: Bool = false) -> some View {
        let valid = !requireValid || (try? MPRules.normalize(code.wrappedValue)) != nil
        return VStack(spacing: 12) {
            Text(label).font(.headline).foregroundStyle(MPStyle.ink)
            TextField(t("6-character code", "קוד בן 6 תווים"), text: Binding(get: { code.wrappedValue }, set: { code.wrappedValue = String($0.uppercased().prefix(6)) }))
                .textInputAutocapitalization(.characters).autocorrectionDisabled().font(.title3.bold()).multilineTextAlignment(.center)
                .foregroundStyle(MPStyle.ink).padding(12).frame(minHeight: 56).background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MPStyle.ink.opacity(0.25), lineWidth: 1)).environment(\.layoutDirection, .leftToRight)
            action(button, color: MPStyle.blue) { let value = code.wrappedValue; Task { await model.join(value) } }
                .foregroundStyle(valid ? MPStyle.ink : Color(red: 0x6b / 255, green: 0x72 / 255, blue: 0x80 / 255))
                .opacity(valid ? 1 : 0.55).disabled(!model.connected || model.busy || !valid)
        }
    }
    /// Android PlayActivity.friendlyOptions (305914e, f0f27c4, c9f5fa6): arena, controls and points (kept for a replay),
    /// the house player, Start, inviting a friend with a new code and joining with a code. Back leaves (no Cancel).
    private var createFriendlyPage: some View {
        ScrollView {
            VStack(spacing: gap) {
                card {
                    Text(t("Create a game, then share its code with a friend or choose a house player.", "צרו משחק, ואז שתפו את הקוד עם חבר או בחרו שחקן בית.")).font(.callout).leadingText()
                    arenaChoice($model.friendlyArena)
                    controlsSection(roomTargets: true)
                    carousel
                    action(t("Start", "התחלת משחק"), face: MPCourtStyle.startFace) { Task { await model.create(.friendly, house: model.selectedPlayer) } }
                    if model.online {
                        action(t("Invite a friend by code", "הזמינו חבר באמצעות קוד"), color: MPStyle.lilac) { Task { await model.create(.friendly, house: nil) } }.disabled(!model.connected)
                        MPDashedDivider()
                        joinForm(code: $friendlyCode, label: t("Or join with a code", "או הצטרפו באמצעות קוד"), button: t("Join with a code", "הצטרפות באמצעות קוד"), requireValid: true)
                    }
                }
            }.frame(maxWidth: 680).padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
    }
    /// Android createForm "Arena" (c9f5fa6): the selected arena and its table size ("selected-arena-info").
    private func arenaChoice(_ selection: Binding<MPArena>) -> some View {
        let arena = selection.wrappedValue
        return VStack(spacing: 10) {
            Text(t("Arena", "זירה")).font(.system(size: 19, weight: .bold))
            MPChoiceGrid(title: t("Arena", "זירה"), options: MPArena.choices.map { (value: $0, label: $0.title(he: he)) }, selection: selection)
            Text(arena.title(he: he) + " · " + (arena == .park || arena == .indoors ? t("large table", "שולחן גדול") : t("compact table", "שולחן קומפקטי")))
                .font(.system(size: 16, weight: .bold)).leadingText()
        }
    }
    /// Android PlayActivity.tournamentOptions (c9f5fa6): the host's settings and Create room; Back leaves (no Cancel).
    private var createTournamentPage: some View {
        ScrollView {
            VStack(spacing: gap) {
                tournamentForm
            }.frame(maxWidth: 680).padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity)
        }
    }
    private func toggle(_ key: String) { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } }
    /// Android PlayActivity footer links (2026-10): `FamilyMenu.link` without a backing, pale blue with a dark shadow
    /// so they stay readable on the dark sections and the illustrated setting.
    private func familyLink(_ title: String, color: Color = MPStyle.link, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(size: 17, weight: .bold)).underline().foregroundStyle(color)
                .shadow(color: Color(red: 0x10 / 255, green: 0x20 / 255, blue: 0x39 / 255), radius: 0.5, x: 0, y: 1)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12)
        }.buttonStyle(.plain)
    }
    /// Android `AdCoordinator.familyMenuIdle`, 1.5 s after the home appears: the family remove-ads
    /// reminder (after 14 days, then at most every 14 days); "Remove ads" opens the purchase sheet.
    private func familyMenuIdle() async {
        // Android skips QA and screenshot launches.
        guard model.route == .menu, model.experience == .full, model.ads.configured, StoreScreenshotScene.name == nil else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        // Android `hasWindowFocus()`: no other sheet or alert is up.
        guard !Task.isCancelled, model.route == .menu, !model.busy, !showCommerce, !showHelp, !showGameSettings, model.error == nil else { return }
        FamilyMessages.shared.remind(ownershipResolved: commerce.ownershipResolved, adFree: { [commerce] in commerce.isRemoveAdsActive },
                                     purchaseAvailable: commerce.removeAdsProduct != nil, gate: nil) {
            commerceUnlocked = true
            showCommerce = true
        }
    }
    /// `face`: an Android raised face (PongCourtStyle start / menu) instead of a flat colour.
    private func action(_ title: String, color: Color = MPStyle.blue, face: MPCourtFace? = nil, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.system(.headline, design: .rounded, weight: .bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 64).padding(.horizontal, 8) }
            .buttonStyle(.plain)
            .background { if let face { MPFaceBackground(face: face, radius: 18) } else { RoundedRectangle(cornerRadius: 18).fill(color) } }
            .disabled(model.busy)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: gap, content: content).padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
    }
    private var controls: some View { controlsSection(roomTargets: false) }
    /// Android PlayActivity createForm (96ae066, c9f5fa6): Beginner, Starter, Standard and Pro, and only the selected
    /// control's explanation ("selected-control-info"). `roomTargets`: rooms offer 3, 5, 7 or 11 points; a local match
    /// keeps its level's own targets.
    private func controlsSection(roomTargets: Bool) -> some View {
        let targets = roomTargets ? [3, 5, 7, 11] : model.level.targets
        return VStack(spacing: 14) {
            Text(t("Control difficulty", "רמת השליטה")).font(.system(size: 19, weight: .bold))
            // Owner report 2026-10: the system segmented picker showed no selection on iPad.
            MPChoiceGrid(title: t("Control difficulty", "רמת השליטה"),
                         options: MPLevel.controlChoices.map { (value: $0, label: MPControlChoice.title($0.rawValue, hebrew: he)) },
                         selection: $model.level, columns: 4)
                .onChange(of: model.level) { _, _ in model.saveControls() }
            Text(MPControlChoice.explanation(model.level.rawValue, hebrew: he)).font(.system(size: 16)).leadingText()
            HStack { Text(t("Points to win", "נקודות לניצחון")).font(.system(size: 19, weight: .bold)); Spacer(); Picker(t("Points", "נקודות"), selection: $model.target) { ForEach(targets, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu).font(.title3.bold()) }
        }
        .onAppear { if roomTargets && !targets.contains(model.target) { model.target = 7 } }
    }
    private var carousel: some View {
        VStack(spacing: 16) {
            Text(t("Opponent", "יריב")).font(.headline)
            HStack {
                Button { cycle(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.system(size: 34)).frame(width: 48, height: 60) }.accessibilityLabel(t("Previous player", "השחקן הקודם"))
                VStack(spacing: 14) {
                    MPAvatar(character: model.selectedPlayer.id, icon: 0).frame(height: 150)
                    Text(model.selectedPlayer.name(hebrew: he)).font(.title2.bold()).padding(.vertical, 6)
                }.frame(maxWidth: .infinity).id(model.selectedPlayer.id)
                    .transition(.asymmetric(insertion: .move(edge: carouselDirection > 0 ? .trailing : .leading).combined(with: .opacity), removal: .move(edge: carouselDirection > 0 ? .leading : .trailing).combined(with: .opacity)))
                    .gesture(DragGesture(minimumDistance: 30).onEnded { if abs($0.translation.width) > abs($0.translation.height) { cycle($0.translation.width < 0 ? 1 : -1) } })
                Button { cycle(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.system(size: 34)).frame(width: 48, height: 60) }.accessibilityLabel(t("Next player", "השחקן הבא"))
            }.clipped().environment(\.layoutDirection, .leftToRight)
            let p = model.selectedPlayer.profile
            Text(t("Power \(p.power) · Forehand \(p.forehandSkill) · Backhand \(p.backhandSkill) · Serve \(p.serveSkill)", "עוצמה \(p.power) · כף יד \(p.forehandSkill) · גב יד \(p.backhandSkill) · הגשה \(p.serveSkill)")).font(.caption).multilineTextAlignment(.center)
        }
    }
    private func cycle(_ offset: Int) { carouselDirection = offset; withAnimation(.easeInOut(duration: 0.22)) { model.playerIndex = (model.playerIndex + offset + MPRoster.all.count) % MPRoster.all.count } }
    private var tournamentForm: some View {
        card {
            Text(t("Invite friends with the code and add house players to the same tournament.", "הזמינו חברים באמצעות הקוד והוסיפו שחקני בית לאותו טורניר.")).font(.callout).leadingText()
            // Android PlayActivity "Tournament format": round robin, or a knockout redrawn each round (2…9 players).
            Text(t("Tournament format", "שיטת הטורניר")).font(.headline)
            MPChoiceBar(title: t("Tournament format", "שיטת הטורניר"),
                        options: MPTournamentFormat.allCases.map { (value: $0, label: $0.title(he)) },
                        selection: $tournamentFormat)
                .onChange(of: tournamentFormat) { _, value in model.preferences.knockoutFormat = value == .knockout }
            if tournamentFormat == .knockout {
                Stepper(t("Players: \(knockoutCapacity)", "שחקנים: \(knockoutCapacity)"), value: $knockoutCapacity, in: 2...MPKnockout.maxPlayers).font(.headline)
                Text(t("Pairs are drawn again each round. With an odd number of players, one randomly chosen player advances without playing. Win to stay in!", "בכל סיבוב מוגרלים זוגות מחדש. כשמספר השחקנים אי־זוגי, שחקן אחד נבחר באקראי ועולה בלי לשחק. מנצחים וממשיכים!")).font(.callout).leadingText()
            } else {
                Stepper(t("Players: \(capacity)", "שחקנים: \(capacity)"), value: $capacity, in: 2...8).font(.headline)
                MPChoiceBar(title: t("Rounds", "סבבים"),
                            options: [(value: 1, label: t("One round", "סבב אחד")), (value: 2, label: t("Two rounds", "שני סבבים"))],
                            selection: $legs)
                Stepper(t("Standings points per win: \(winPoints)", "נקודות בטבלה לכל ניצחון: \(winPoints)"), value: $winPoints, in: 1...5).font(.headline)
            }
            arenaChoice($model.tournamentArena)
            controlsSection(roomTargets: true)
            Text(t("Choose your house players on the next screen.", "במסך הבא בחרו את שחקני הבית.")).font(.callout).leadingText()
            if !model.hasSpace(.tournament) { Text(t("You have three open tournaments. Finish or leave one before creating another.", "יש לכם שלושה טורנירים פתוחים. סיימו או עזבו אחד מהם לפני יצירת טורניר נוסף.")).font(.callout).leadingText() }
            action(t("Create room", "יצירת חדר")) {
                let knockout = tournamentFormat == .knockout
                Task { await model.create(.tournament, capacity: knockout ? knockoutCapacity : capacity, legs: legs, winPoints: winPoints, format: tournamentFormat, house: nil) }
            }.disabled(!model.connected)
        }
        .onAppear { tournamentFormat = model.preferences.knockoutFormat ? .knockout : .roundRobin }
    }
    private var profileEditor: some View {
        card {
            Text(t("Choose your avatar", "בחרו דמות")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(MPRoster.all) { player in
                    Button { avatarCharacter = player.id } label: {
                        VStack { MPAvatar(character: player.id, icon: 0).frame(height: 64); Text(player.name(hebrew: he)).font(.caption).lineLimit(1) }
                            .padding(4).background(avatarCharacter == player.id ? MPStyle.mint : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                ForEach(0..<MPNames.icons.count, id: \.self) { index in
                    Button { avatarCharacter = ""; avatarIndex = index } label: { Text(MPNames.icons[index]).font(.largeTitle).frame(maxWidth: .infinity, minHeight: 72).background(avatarCharacter.isEmpty && avatarIndex == index ? MPStyle.mint : .clear, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                }
            }
            // Android profileForm (2026-10): the choice is a label, not a separate "Use this character" button.
            Text(avatarCharacter.isEmpty ? t("Icon selected", "נבחר סמל") : t("Selected: ", "נבחרה: ") + (MPRoster.find(avatarCharacter)?.name(hebrew: he) ?? ""))
                .font(.system(size: 18, weight: .bold)).foregroundStyle(MPStyle.ink).frame(maxWidth: .infinity, minHeight: 52)
                .background(MPStyle.mint, in: RoundedRectangle(cornerRadius: 16))
            HStack {
                Button { nicknameIndex = (nicknameIndex + 99) % 100 } label: { Image(systemName: "chevron.left.circle.fill").font(.title).frame(width: 44, height: 48) }
                Text(MPNames.candidate(nicknameIndex, hebrew: he, character: avatarCharacter)).font(.headline).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                Button { nicknameIndex = (nicknameIndex + 1) % 100 } label: { Image(systemName: "chevron.right.circle.fill").font(.title).frame(width: 44, height: 48) }
            }.environment(\.layoutDirection, .leftToRight)
            action(t("Save nickname & avatar", "שמירת כינוי ודמות"), color: MPStyle.mint) { Task { await model.profile(index: nicknameIndex, avatar: avatarIndex, character: avatarCharacter); if model.error == nil { expanded.remove("profile") } } }.disabled(!model.connected)
        }
    }
    /// Android PlayActivity.history (36fbbb4): purple raised sections and white saved items; an empty list reads
    /// "Saved games (0)" without a sign and cannot be opened.
    private func roomSection(_ kind: MPSessionKind) -> some View {
        let key = kind.path, rooms = model.rooms.filter { $0.kind == kind }, open = expanded.contains(key) && !rooms.isEmpty
        return VStack(spacing: open ? gap : 0) {
            Button { if !rooms.isEmpty { toggle(key) } } label: {
                HStack {
                    if !rooms.isEmpty { Text(open ? "−" : "+").font(.system(size: 30, weight: .heavy)).foregroundStyle(MPStyle.ink).frame(width: 36, height: 40) }
                    Text((kind == .friendly ? t("Saved games", "משחקים שמורים") : t("Saved tournaments", "טורנירים שמורים")) + " (\(rooms.count))" + (rooms.isEmpty ? "" : ":")).font(.headline.bold()).foregroundStyle(MPStyle.ink)
                    Spacer()
                }.padding(.horizontal, 12).frame(minHeight: 64)
            }.buttonStyle(.plain).background(MPFaceBackground(face: MPCourtStyle.savedFace, radius: MPCourtStyle.savedItemRadius))
            if open {
                // Android keeps this line although an empty list no longer opens.
                if rooms.isEmpty { Text(t("Nothing here yet. Start one above!", "עוד אין כאן משחקים. אפשר להתחיל למעלה!")).foregroundStyle(MPStyle.ink).leadingText().padding(12) }
                ForEach(rooms) { s in
                    Button { model.enter(s) } label: {
                        VStack(spacing: 6) { Text((kind == .friendly ? t("Friendly game", "משחק ידידות") : t("Tournament", "טורניר")) + " (\(s.code))").font(.headline); Text(s.complete ? t("Finished", "הסתיים") : t("Continue", "המשך")).font(.callout) }.foregroundStyle(MPStyle.ink).frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.plain).background(MPFaceBackground(face: MPCourtStyle.savedItemFace, radius: MPCourtStyle.savedItemRadius))
                }.padding(.horizontal, 6).padding(.bottom, 8)
            }
        }.padding(open ? 6 : 0)
        .background { if open { MPFaceBackground(face: MPCourtStyle.savedFace, radius: MPCourtStyle.savedRadius) } }
    }
    private var lobby: some View {
        ScrollView {
            if let s = model.session {
                VStack(spacing: gap) {
                    if model.online && !s.complete && !model.challenge(s) {
                        Button { UIPasteboard.general.string = s.code; copied = true } label: { Label(s.code, systemImage: "doc.on.doc").font(.title2.bold()).padding(14).frame(maxWidth: .infinity) }.background(MPStyle.blue, in: RoundedRectangle(cornerRadius: 16)).environment(\.layoutDirection, .leftToRight)
                        Text(copied ? t("Code copied", "הקוד הועתק") : t("Tap to copy and share this code with a friend.", "געו להעתקת הקוד ושתפו אותו עם חבר.")).font(.callout)
                    }
                    // Android renderRoom: the room's arena (newer rooms) and its control level.
                    if !s.arena.isEmpty { Text(t("Arena: ", "זירה: ") + MPArena.read(s.arena).title(he: he)).font(.system(size: 16)) }
                    Text(t("Controls: ", "רמת השליטה: ") + MPControlChoice.title(s.difficulty, hebrew: he)).font(.callout.bold())
                    if s.complete { completedRoom(s) } else { openRoom(s) }
                }.frame(maxWidth: 720).padding(20).frame(maxWidth: .infinity)
            }
        }
    }
    /// Android PlayActivity.completed (78ed219, 36fbbb4): the headline; a tournament keeps its podium, table or bracket and
    /// all matches visible until Back; a friendly game offers Done. A completed room is not kept in history.
    @ViewBuilder private func completedRoom(_ s: MPSession) -> some View {
        if s.kind == .tournament {
            VStack(spacing: gap) {
                Text(MPCompletionText.headline(s, model.userID, hebrew: he)).font(.system(size: 23, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                MPRoomsPodium(session: s, hebrew: he)
            }.padding(16).frame(maxWidth: .infinity).background(MPStyle.mint, in: RoundedRectangle(cornerRadius: 18))
            if s.knockout { bracket(s) } else { standings(s) }
            allMatches(s)
        } else {
            card {
                Text(MPCompletionText.headline(s, model.userID, hebrew: he)).font(.system(size: 23, weight: .bold)).multilineTextAlignment(.center)
                action(t("Done", "סיום"), color: MPStyle.mint) { model.dismissCompleted() }.padding(.top, 12)
            }
            ForEach(s.matches.values.sorted { $0.id < $1.id }) { fixtureRow(s, $0, interactive: false) }
        }
    }
    /// Android PlayActivity.allMatches (36fbbb4): every fixture behind a collapsed expander.
    @ViewBuilder private func allMatches(_ s: MPSession) -> some View {
        Button { toggle("allMatches") } label: { HStack { Text(t("All matches", "כל המשחקים") + " (\(s.matches.count))").font(.headline); Spacer(); Text(expanded.contains("allMatches") ? "−" : "+").font(.largeTitle.bold()) }.padding(16) }.buttonStyle(.plain).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 18))
        if expanded.contains("allMatches") { ForEach(s.matches.values.sorted { $0.id < $1.id }) { fixtureRow(s, $0, interactive: false) } }
    }
    @ViewBuilder private func openRoom(_ s: MPSession) -> some View {
        if s.kind == .friendly { friendlyRoom(s) } else { tournamentRoom(s) }
    }
    @ViewBuilder private func friendlyRoom(_ s: MPSession) -> some View {
        friendlyParticipants(s)
        if s.state == "WAITING" && s.host == model.userID {
            if s.participants.count < s.capacity {
                Text(t("Add a house player, or let a friend join using the code.", "הוסיפו שחקן בית, או הזמינו חבר באמצעות הקוד.")).multilineTextAlignment(.center)
                carousel
                action(t("Add \(model.selectedPlayer.name(hebrew: he))", "הוסיפו את \(model.selectedPlayer.name(hebrew: he))")) { Task { await model.addHouse(model.selectedPlayer) } }
                    .disabled(s.participants.values.contains { $0.bot?.characterId == model.selectedPlayer.id })
            }
            if s.participants.count == s.capacity { action(t("Continue", "המשך")) { Task { await model.startTournament() } } }
        }
        ForEach(s.matches.values.filter { $0.contains(model.userID) && !$0.terminal }.sorted { $0.id < $1.id }) { match in fixtureRow(s, match) }
        ForEach(s.matches.values.filter { $0.terminal }.sorted { $0.id < $1.id }) { fixtureRow(s, $0, interactive: false) }
        // Android PlayActivity.friendly (2026-10, c9f5fa6): "Save for later" and the pink Finish only once play has started;
        // Back leaves (deletes) an unstarted game.
        let played = s.matches.values.contains { $0.phase == .playing || $0.phase == .finished }
        if played { action(t("Save for later", "שמירה להמשך"), face: MPCourtStyle.menuFace) { model.saveFriendlyForLater() } }
        if played && MPRules.canFinishFriendly(s, actor: model.userID) {
            action(t("Finish", "סיום"), color: MPStyle.pink) { Task { await model.leave(delete: true) } }.foregroundStyle(.white).padding(.top, 12)
        }
    }
    /// Android PlayActivity.tournament (2026-10): the waiting roster with skills, a persistent house-player picker and
    /// Start for the host; after the start, progress, the player's own matches and the bracket or all matches. The
    /// pink Delete / Leave button comes after Start and the player's matches.
    @ViewBuilder private func tournamentRoom(_ s: MPSession) -> some View {
        let mine = s.matches.values.filter { $0.contains(model.userID) && !$0.terminal }.sorted { $0.id < $1.id }
        if s.state == "WAITING" {
            waitingRoster(s)
            if s.host == model.userID {
                if s.participants.count < s.capacity {
                    let used = Set(s.participants.values.compactMap { $0.bot?.characterId })
                    card {
                        MPHousePicker(hebrew: he, selected: $houseChoice, excluded: used)
                        action(t("Add player", "הוספת שחקן"), color: MPStyle.mint) {
                            if let player = MPRoster.find(houseChoice), !used.contains(player.id) { Task { await model.addHouse(player) } }
                        }
                    }
                }
                action(t("Start tournament", "התחלת הטורניר"), color: MPStyle.mint) { Task { await model.startTournament() } }
                    .disabled(s.participants.count != s.capacity).opacity(s.participants.count == s.capacity ? 1 : 0.5)
            } else {
                card { Text(t("The host will start when everyone has joined.", "המארח יתחיל לאחר שכולם יצטרפו.")).leadingText() }
            }
            tournamentExitButton(s)
        } else {
            card {
                if s.knockout {
                    let remaining = MPKnockout.matches(s, MPKnockout.current(s)).filter { !$0.terminal }.count
                    Text(t("Matches remaining this round: \(remaining)", "משחקים שנותרו בסיבוב הזה: \(remaining)")).font(.headline).multilineTextAlignment(.center)
                    Text(MPKnockout.stage(s, hebrew: he)).font(.title2.bold())
                } else {
                    let finished = s.matches.values.filter { $0.phase == .finished }.count
                    let remaining = s.matches.values.filter { !$0.terminal }.count
                    Text(t("Finished: \(finished)  •  Remaining: \(remaining)", "הסתיימו: \(finished)  •  נותרו: \(remaining)")).font(.headline).multilineTextAlignment(.center)
                }
            }
            if !s.knockout { standings(s) }
            VStack(spacing: gap) {
                if s.knockout { Text(MPKnockout.playerStatus(s, model.userID, hebrew: he)).font(.headline).multilineTextAlignment(.center) }
                else if mine.isEmpty { Text(t("Your matches are complete. Waiting for the other players to finish the tournament.", "המשחקים שלכם הסתיימו. ממתינים לשאר השחקנים לסיום הטורניר.")).leadingText() }
                else { Text(t("Next / playable games", "המשחקים הבאים שאפשר לשחק")).font(.title3.bold()).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 64) }
            }.padding(16).frame(maxWidth: .infinity).background(MPStyle.mint, in: RoundedRectangle(cornerRadius: 18))
            ForEach(mine) { match in fixtureRow(s, match) }
            tournamentExitButton(s)
            if s.knockout { bracket(s) } else { allMatches(s) }
        }
    }
    /// Android `tournamentExitButton`: pink, after Start, and confirmed before anything is deleted or left.
    private func tournamentExitButton(_ s: MPSession) -> some View {
        let delete = MPRules.canDelete(s, actor: model.userID)
        return action(delete ? t("Delete", "מחיקה") : t("Leave tournament", "עזיבת הטורניר"), color: MPStyle.pink) { confirmExit = true }
            .foregroundStyle(.white).padding(.top, 24)
    }
    /// Android `waitingRoster`: people and house players with full-body portraits and skills out of 10 (people have
    /// dashes, never invented ratings). The host removes a house player with the red X.
    private func waitingRoster(_ s: MPSession) -> some View {
        let host = s.host == model.userID
        let skills = [t("Speed", "מהירות"), t("Reaction", "תגובה"), t("Accuracy", "דיוק"), t("Power", "עוצמה"), t("Agility", "זריזות"), t("Forehand", "כף יד"), t("Backhand", "גב יד"), t("Serve", "הגשה")]
        let rows = s.roster.compactMap { id -> MPRosterRow? in s.participants[id].map { MPRosterRow(id: id, participant: $0) } }
        let count = MPMatchText.ordered("\(s.participants.count) / \(s.capacity)")
        return card {
            Text(t("Players", "שחקנים")).font(.title3.bold())
            Text(t("\(count) players · Skills out of 10", "\(count) שחקנים · יכולות מתוך 10")).font(.callout).multilineTextAlignment(.center)
            Text(t("Swipe sideways to see every skill", "החליקו לצדדים כדי לראות את כל היכולות")).font(.caption).leadingText()
            ScrollView(.horizontal) {
                VStack(spacing: 5) {
                    HStack(spacing: 0) {
                        Text(t("Player", "שחקן")).frame(width: 140)
                        if host { Text(t("Remove", "הסרה")).frame(width: 64) }
                        ForEach(skills, id: \.self) { Text($0).frame(width: 72) }
                    }.font(.system(size: 14, weight: .bold)).foregroundStyle(MPStyle.ink).frame(height: 56).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 9))
                    ForEach(rows.indices, id: \.self) { index in rosterRow(rows[index], index: index, host: host) }
                }
            }
            .defaultScrollAnchor(he ? UnitPoint.trailing : UnitPoint.leading)
            .environment(\.layoutDirection, .leftToRight)
        }
    }
    private func rosterRow(_ row: MPRosterRow, index: Int, host: Bool) -> some View {
        let p = row.participant
        let values: [Int]? = p.bot.map { [$0.speed, $0.reaction, $0.accuracy, $0.power, $0.agility, $0.forehandSkill, $0.backhandSkill, $0.serveSkill] }
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                MPAvatar(character: p.bot?.characterId ?? p.identity.characterId, icon: p.identity.avatar).frame(width: 48, height: 70)
                Text(p.name(hebrew: he)).font(.system(size: 15, weight: .bold)).lineLimit(3).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            }.frame(width: 140)
            if host {
                Group {
                    if p.bot != nil {
                        Button { Task { await model.removeHouse(row.id) } } label: { MPRemoveMark().frame(width: 48, height: 48) }
                            .buttonStyle(.plain).accessibilityLabel(t("Remove \(p.name(hebrew: he))", "הסרת \(p.name(hebrew: he))"))
                    } else { Text("—") }
                }.frame(width: 64)
            }
            ForEach(0..<8, id: \.self) { k in Text(values.map { String($0[k]) } ?? "—").frame(width: 72) }
        }.font(.system(size: 14)).foregroundStyle(MPStyle.ink).frame(height: 78)
            .background(index % 2 == 0 ? Color(red: 231 / 255, green: 251 / 255, blue: 244 / 255) : Color(red: 241 / 255, green: 237 / 255, blue: 1), in: RoundedRectangle(cornerRadius: 9))
    }
    /// Android KnockoutBracketView inside a sideways scroll; Hebrew starts at the right-hand end.
    private func bracket(_ s: MPSession) -> some View {
        card {
            Text(s.complete ? t("Tournament bracket", "עץ הטורניר") : MPKnockout.stage(s, hebrew: he)).font(.title2.bold())
            Text(t("Swipe sideways to follow the bracket. Pairs are drawn again each round.", "החליקו לצדדים לצפייה בעץ. הזוגות מוגרלים מחדש בכל סיבוב.")).font(.caption).leadingText()
            ScrollView(.horizontal) { MPKnockoutBracketView(session: s, hebrew: he) }
                .defaultScrollAnchor(he ? UnitPoint.trailing : UnitPoint.leading)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
    private func friendlyParticipants(_ s: MPSession) -> some View {
        HStack(spacing: 24) {
            ForEach(s.roster, id: \.self) { id in if let p = s.participants[id] {
                VStack(spacing: 12) { MPAvatar(character: p.identity.characterId, icon: p.identity.avatar).frame(height: 120); Text(p.name(hebrew: he)).font(.headline).lineLimit(1).minimumScaleFactor(0.55).multilineTextAlignment(.center); Text(s.connected(id) ? t("Connected", "מחובר") : t("Away", "לא מחובר")).font(.caption) }.frame(maxWidth: .infinity)
            } }
        }.padding(.vertical, 16)
    }
    private func standings(_ s: MPSession) -> some View { MPRoomsStandings(session: s, hebrew: he) }
    private func fixtureRow(_ s: MPSession, _ match: MPFixture, interactive: Bool = true) -> some View {
        card {
            Text([match.a, match.b].compactMap { s.participants[$0]?.name(hebrew: he) }.joined(separator: "  —  ")).font(.headline).multilineTextAlignment(.center)
            if match.phase == .finished { Text("\(match.scoreA) – \(match.scoreB)").font(.title2.bold()).environment(\.layoutDirection, .leftToRight) }
            else if match.phase == .cancelled { Text(t("Not finished", "לא הסתיים")) }
            else if houseOnly(s, match) && match.phase != .playing {
                // Android matchRow (2026-10): against house players only, the match is "Not started" until this player
                // presses Start; no Ready step, and one match at a time.
                Text(t("Not started", "טרם התחיל")).font(.headline)
                if interactive {
                    let busy = s.matches.values.contains { $0.id != match.id && $0.phase == .playing && $0.contains(model.userID) }
                    if busy { Text(t("Finish your current match before starting another.", "סיימו את המשחק הנוכחי לפני התחלת משחק נוסף.")).leadingText() }
                    action(t("Start", "התחלה"), color: MPStyle.mint) { Task { await model.startHouseMatch(match) } }.disabled(busy).opacity(busy ? 0.5 : 1)
                }
            }
            else {
                HStack { ForEach([match.a, match.b], id: \.self) { id in if s.participants[id]?.bot == nil { Label(s.participants[id]?.name(hebrew: he) ?? "", systemImage: match.ready[id] == true ? "checkmark.circle.fill" : "circle").font(.callout) } } }
                if interactive && match.contains(model.userID) {
                    action(match.phase == .playing ? t("Continue game", "המשך המשחק") : match.ready[model.userID] == true ? t("Ready — waiting for the other player", "מוכנים — ממתינים לשחקן השני") : t("Ready", "מוכנים"), color: MPStyle.mint) { Task { await model.ready(match) } }
                }
            }
        }
    }
    /// This player is the match's only human (Android `houseOnly`).
    private func houseOnly(_ s: MPSession, _ match: MPFixture) -> Bool { [match.a, match.b].filter { s.human($0) } == [model.userID] }
    /// Android ModernActivity / PrivateMatchActivity (e3bb8c2, 0e65e52): "You 3 · Kyra 5" with each name in its colour
    /// rank (the opponent in theirs, the challenged colour, or the second team colour), outlined; a status line with a
    /// shadow under it. In landscape the tools, score and coaching move into a side gutter and the court stays
    /// centred between equal gutters.
    private var game: some View {
        GeometryReader { proxy in
            if landscapeGame {
                let gutter = min(192, max(144, proxy.size.width * 0.19))
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        backButton { model.back() }.frame(width: 64, height: 48)
                        HStack(spacing: 4) { pauseButton; if model.session == nil { settingsButton } }.frame(height: 48)
                        ScrollView {
                            VStack(spacing: 14) {
                                scoreText(stacked: true).font(.system(size: 24, weight: .bold))
                                statusText(wide: true)
                            }.padding(2).frame(maxWidth: .infinity, minHeight: proxy.size.height - 220)
                        }
                        Spacer().frame(height: model.session == nil ? 96 : 48)
                    }.padding(.horizontal, 8).padding(.vertical, 4).frame(width: gutter)
                    court
                    Color.clear.frame(width: gutter).accessibilityHidden(true)
                }
            } else {
                VStack(spacing: 0) {
                    scoreText(stacked: false).font(.system(size: 19, weight: .bold)).lineLimit(2).minimumScaleFactor(0.7).padding(.horizontal, 18).padding(.vertical, 6)
                    if model.session == nil {
                        Button { openGameSettings() } label: { Label(t("Settings", "הגדרות"), systemImage: "gearshape.fill").font(.headline).padding(8) }.foregroundStyle(.white)
                    }
                    statusText(wide: false).padding(.horizontal, 12).padding(.top, 3).padding(.bottom, 7)
                    court
                }
            }
        }
        .overlay(alignment: .bottom) {
            if landscapeTip {
                Text(t("For a wider view, play in landscape.", "לתצוגה רחבה יותר, שחקו במצב אופקי.")).font(.callout.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 12).background(Color.black.opacity(0.75), in: Capsule())
                    .padding(.horizontal, 24).padding(.bottom, 28).allowsHitTesting(false).transition(.opacity)
            }
        }
        .onChange(of: wide) { _, value in MPLandscapeTipSession.shared.observe(value); if value { landscapeTip = false } }
        .task(id: model.scene.map { ObjectIdentifier($0) }) {
            // Android PongOrientationHint.show: 0.9 s after the court appears, once per run, only in portrait.
            MPLandscapeTipSession.shared.observe(wide)
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            MPLandscapeTipSession.shared.observe(wide)
            let active = model.route == .game && model.scene?.engine.score.winner == nil
            guard !wide, MPLandscapeTipSession.shared.claim(active) else { return }
            withAnimation { landscapeTip = true }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation { landscapeTip = false }
        }
    }
    private func openGameSettings() { if !model.paused { model.togglePause() }; showGameSettings = true }
    private var pauseButton: some View {
        Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.title2).frame(width: 48, height: 48) }
            .foregroundStyle(.white).accessibilityLabel(model.paused ? t("Resume", "המשך") : t("Pause", "השהיה"))
    }
    private var settingsButton: some View {
        Button { openGameSettings() } label: { Image(systemName: "gearshape.fill").font(.title2).frame(width: 48, height: 48) }
            .foregroundStyle(.white).accessibilityLabel(t("Settings", "הגדרות"))
    }
    @ViewBuilder private var court: some View {
        if let scene = model.scene {
            // The court's scenery lines up with the full-screen arena behind the HUD (MPScene.backdropFrame).
            GeometryReader { proxy in
                SpriteView(scene: scene).id(ObjectIdentifier(scene))
                    .accessibilityLabel(t("Ping Pong table. Tap to serve or return; swipe diagonally to aim.", "שולחן פינג פונג. נגיעה להגשה או להחזרה; החלקה באלכסון לכיוון."))
                    .onAppear { alignBackdrop(scene, proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in alignBackdrop(scene, frame) }
            }
        } else { Spacer() }
    }
    private func alignBackdrop(_ scene: MPScene, _ court: CGRect) {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? court.size
        scene.backdropFrame = MPArenaPageBackdrop.available(scene.selectedArena) ? CGRect(x: -court.minX, y: -court.minY, width: screen.width, height: screen.height) : nil
    }
    /// Android `PongTeamColors.named` with the colour ranks: a navy contour for a local match, a luminance-adaptive
    /// contour for a room match (Android `adaptiveOutline`).
    private func scoreText(stacked: Bool) -> some View {
        let _ = model.rankRevision
        let local = model.experience == .full ? model.ranking.rank.color : MPTeamColors.fill(0)
        let other = model.session != nil ? model.opponentRankColor : MPTeamColors.fill(1)
        return MPHudText([.init(text: t("You", "אתם") + " \(model.childScore)", color: local), .init(text: stacked ? "\n" : " · ", color: 0xffffffff),
                          .init(text: opponentName + " \(model.opponentScore)", color: other)],
                         font: .system(size: stacked ? 24 : 19, weight: .bold), outline: model.session != nil ? 1.6 : 2.8, adaptive: model.session != nil)
    }
    /// Android status line: white (pale blue for a portrait local match) with a navy shadow; the serve tip is
    /// start-aligned (PongHelpTips.align).
    private func statusText(wide: Bool) -> some View {
        let tip = model.serveTip && !model.paused && model.gameWarning == nil
        let color: Color = !wide && model.session == nil ? Color(red: 188 / 255, green: 232 / 255, blue: 1) : .white
        return Text(gameStatus).font(.system(size: wide ? 15 : 16, weight: .bold)).foregroundStyle(color)
            .multilineTextAlignment(tip ? .leading : .center).lineLimit(wide ? 12 : 3)
            .frame(maxWidth: .infinity, minHeight: wide ? 0 : 40, alignment: tip ? .leading : .center)
            .shadow(color: MPColor.color(0xff10243b), radius: 2, x: 0, y: 1)
            .accessibilityAddTraits(.updatesFrequently).allowsHitTesting(false)
    }
    private var opponentName: String {
        if let s = model.session, let m = model.fixture, let p = s.participants[m.a == model.userID ? m.b : m.a] { return model.shownName(s, p) }; return model.selectedPlayer.name(hebrew: he)
    }
    /// Android PrivateMatchActivity status (6feaac5): a knockout match is prefixed with its stage; the control level is
    /// no longer repeated during play.
    private var gameStatus: String {
        // A connection problem is a status line, never a dialog over the court (owner report 2026-10).
        if let warning = model.gameWarning, !model.paused { return warning }
        let text = gameStatusText
        guard let s = model.session, !model.paused else { return text }
        return (s.knockout ? MPKnockout.stage(s, hebrew: he) + " · " : "") + text
    }
    /// A room match against a house player waits only for the internet, never for "the other player".
    private var opponentIsHouse: Bool {
        guard let s = model.session, let m = model.fixture else { return true }
        return s.participants[m.a == model.userID ? m.b : m.a]?.bot != nil
    }
    private var gameStatusText: String {
        if model.paused { return t("Paused", "המשחק מושהה") }
        let text: String
        switch model.status {
        case "WAITING": return opponentIsHouse ? t("Waiting for the internet connection…", "ממתינים לחיבור לאינטרנט…") : t("Waiting for the other player to return…", "ממתינים לחזרת השחקן השני…")
        case "TAP_SERVE": return t("Tap a point on the table to aim your serve", "געו בנקודה בשולחן כדי לכוון את ההגשה")
        // Android 838c209: a serve drag repositions; a separate tap serves.
        case "SWIPE_SERVE": return t("Drag to move. Lift your finger, then tap to serve.", "גררו כדי לזוז. הרימו את האצבע, ואז הקישו כדי להגיש.")
        case "RETURN_BALL": return t("Return the ball", "החזירו את הכדור")
        case "AUTO_HINT": return t("Move your paddle to the ball on your side. It hits automatically!", "הזיזו את המחבט אל הכדור בצד שלכם. החבטה אוטומטית!")
        case "CHILD_WIN", "MINIK_WIN":
            if model.session != nil { return t("Saving the result…", "שומרים את התוצאה…") }
            return model.status == "CHILD_WIN" ? t("You won the match!", "ניצחתם במשחק!") : t("Match over. Well played!", "המשחק הסתיים. שיחקתם יפה!")
        // Owner report 2026-10: say what really happened, and who won the point.
        case "NET_FAULT": text = t("The ball hit the net", "הכדור פגע ברשת")
        case "OUT_FAULT": text = t("The ball flew off the table", "הכדור עף אל מחוץ לשולחן")
        case "SHORT_FAULT": text = t("The ball didn’t cross the net", "הכדור לא עבר את הרשת")
        case "SECOND_BOUNCE": text = t("The ball bounced twice", "הכדור קפץ פעמיים")
        case "BALL_IN": text = t("The ball wasn’t returned", "הכדור לא הוחזר")
        case "INVALID_SERVE": text = t("The serve must bounce on both sides", "ההגשה חייבת לקפוץ בשני הצדדים")
        default: return t("Tap to return · Swipe diagonally to aim", "נגיעה להחזרה · החלקה באלכסון לכיוון")
        }
        // Android PongHelpTips (aca67f4): a serve that bounced twice on the far side explains the rule instead.
        if model.serveTip && model.pointWinner == .child { return MPHelpTips.serveDoubleBouncePoint(he: he) }
        guard let winner = model.pointWinner else { return text }
        return text + " · " + (winner == .child ? t("Your point!", "נקודה לכם!") : t("Point to \(opponentName)", "נקודה ל־\(opponentName)"))
    }
    private var gameSettings: some View {
        NavigationStack { ScrollView { VStack(spacing: 18) {
            if model.experience == .full { MPReceptionSettingsView(hebrew: he, open: $receptionOpen) }
            if model.practice {
                Text(t("Minik level", "הרמה של מיניק")).font(.headline)
                Picker(t("Minik level", "הרמה של מיניק"), selection: $model.practiceLevel) {
                    Text(t("Beginner", "מתחילים")).tag(MPLevel.beginner)
                    Text(t("Easy", "קלה")).tag(MPLevel.easy); Text(t("Medium", "בינונית")).tag(MPLevel.medium)
                    Text(t("Hard", "קשה")).tag(MPLevel.hard); Text(t("Super hard", "סופר קשה")).tag(MPLevel.superHard)
                }.pickerStyle(.menu).font(.title3.bold())
                Text(t("Beginner hits automatically when your paddle is in place. Easy, Medium and Hard use forgiving taps and diagonal swipes. Super hard requires precise swipes.", "במתחילים המחבט חובט אוטומטית כשהוא במקום. קל, בינוני וקשה משתמשים בנגיעות ובהחלקות אלכסוניות סלחניות. סופר קשה דורש החלקות מדויקות.")).multilineTextAlignment(.center)
            } else { controls }
            action(t("Start a new game", "התחלת משחק חדש")) { model.startSingle(practice: model.practice); showGameSettings = false }
            action(t("Continue game", "המשך המשחק"), color: MPStyle.mint) { showGameSettings = false }
        }.padding(24) }.navigationTitle(t("Settings", "הגדרות")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { backButton { showGameSettings = false } } } }
        // The sheet is its own presentation: the ball-assistance texts are dark ink, so it stays light in Dark Mode.
        .preferredColorScheme(.light)
    }
    private var guide: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape { HStack(spacing: 8) { guideCourt; ScrollView { guideControls }.frame(width: min(350, geometry.size.width * 0.46)) } }
                else { VStack(spacing: 8) { if model.scene != nil { guideCourt.frame(maxHeight: geometry.size.height * 0.48) }; ScrollView { guideControls } } }
            }.padding(.horizontal, 12).padding(.bottom, 12)
        }
    }
    @ViewBuilder private var guideCourt: some View {
        // Every lesson try installs a new scene: the view's identity follows it, as in Multi Ping Pong. Without it
        // the first, paused table stayed on screen and the buttons seemed dead (owner's video, 2026-10-14).
        if let scene = model.scene { SpriteView(scene: scene).id(ObjectIdentifier(scene)).clipShape(RoundedRectangle(cornerRadius: 16)).allowsHitTesting(model.tutorialPhase == .attempt) }
        else { Image("mp_minik_motion_ready").resizable().scaledToFit().frame(maxHeight: 220).accessibilityHidden(true) }
    }
    /// Android GuideDialog (2026-10): the lesson text and secondary actions scroll; the two primary actions stay below.
    private var guideControls: some View {
        VStack(spacing: 12) {
            ScrollView { guideContent }
            HStack(spacing: 12) {
                action(t("Show me", "הראו לי"), color: MPStyle.lilac) { model.tutorialStart(demo: true) }
                action(model.tutorialPhase == .feedback ? t("Try again", "נסו שוב") : t("Try it yourself", "נסו בעצמכם"), color: MPStyle.mint) { model.tutorialStart(demo: false) }
            }
        }.padding(.horizontal, 4).padding(.bottom, 12)
        .onAppear { refreshGuideTip() }
        .onChange(of: model.tutorialPhase) { _, _ in refreshGuideTip() }
        .onChange(of: model.tutorialStep) { _, _ in refreshGuideTip() }
    }
    /// Android `PongHelpTips.next(eligible = SERVE_MIDDLE)` each time a lesson card explains itself.
    private func refreshGuideTip() {
        guideTip = model.tutorialPhase == .explanation ? MPHelpTips.next(he: he, eligible: model.tutorialStep == .serveMiddle) : ""
    }
    private var guideContent: some View {
        VStack(spacing: 12) {
            Text("\(model.tutorialStep.rawValue + 1) / \(MPTutorialStep.allCases.count)").font(.caption.bold())
            Text(model.tutorialStep.title(he)).font(.title3.bold()).multilineTextAlignment(.center)
            Text(model.tutorialStep.instruction(he) + guideTip).font(.callout).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if model.tutorialPhase == .demonstration || model.tutorialPhase == .attempt {
                // Android guide_spin_hint: the spin lessons are swiped, not tapped.
                Text(model.tutorialPhase == .demonstration ? t("Watch how it’s done", "צפו איך עושים את זה") : model.tutorialStep.hint(he) ?? t("Your turn! Tap the table.", "עכשיו תורכם! געו בשולחן."))
                    .font(.headline).foregroundStyle(MPStyle.pink).multilineTextAlignment(.center)
            }
            if model.tutorialPhase == .feedback {
                Label(guideFeedback, systemImage: model.tutorialSuccess ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill").font(.headline).foregroundStyle(model.tutorialSuccess ? Color.green : MPStyle.pink)
            }
            if model.tutorialPhase == .explanation || model.tutorialPhase == .feedback { action(t("Next", "הבא")) { model.tutorialNext() } }
            action(t("To the game", "למשחק")) { model.guideToGame() }
            if model.experience == .full && model.tutorialStep == .serveMiddle && model.tutorialPhase == .explanation {
                action(t("Learn team play", "לומדים משחק קבוצתי"), color: MPStyle.blue) { model.openJourney(.teams) }
            }
            Toggle(t("Don’t show the guide automatically", "לא להציג את ההדרכה באופן אוטומטי"), isOn: $model.skipGuide).font(.callout).padding(.vertical, 8)
        }.padding(.horizontal, 4)
    }
    private var guideFeedback: String {
        if model.tutorialStep == .autoReturn {
            return model.tutorialSuccess ? t("Great positioning! Your paddle hit automatically and returned the ball to Minik.", "מיקום מצוין! המחבט חבט אוטומטית והחזיר את הכדור למיניק.") :
                t("Move your paddle into the incoming ball’s path on your side. You can get there early and lift your finger; no tap timing is needed.", "הזיזו את המחבט למסלול הכדור בצד שלכם. אפשר להגיע מוקדם ולהרים את האצבע — אין צורך לתזמן הקשה.")
        }
        return model.tutorialSuccess ? t("Well done! The ball landed in the right area.", "כל הכבוד! הכדור נחת באזור הנכון.") : t("Try again. Watch the timing and where the ball lands.", "נסו שוב. שימו לב לתזמון ולמקום שבו הכדור נוחת.")
    }
    /// Android MatchResultDialog (bcee181, 47c70ab): headline, winner, both players' cards and the actions — Play again for a
    /// friendly or local match, then Back to menu / Back to tournament / Back to Color Challenge.
    @ViewBuilder private var result: some View {
        if let result = model.matchResult {
            let _ = model.rankRevision
            MPMatchResultView(result: result, localRank: model.experience == .full ? model.ranking.rank : MPRanks.all[0], hebrew: he,
                              again: { model.playAgainFromResult() }, close: { if model.session != nil { model.closeResult() } else { model.back() } })
        } else { Spacer() }
    }
    private var help: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 22) {
            Text(t("Serve", "הגשה")).font(.title2.bold())
            Text(t("Tap any point on the table to aim your serve. The first bounce is on your side; the second is on the opponent’s side.", "געו בכל נקודה בשולחן כדי לכוון אליה את ההגשה. הקפיצה הראשונה בצד שלכם והשנייה בצד היריב."))
            Text(t("Return and aim", "החזרה וכיוון")).font(.title2.bold())
            Text(t("Tap when the ball reaches your paddle for a forgiving return that keeps its natural sideways direction. Swipe diagonally forward and left or right to choose the landing side, including a wide cross-table shot.", "געו כשהכדור מגיע למחבט כדי להחזיר בסלחנות ולשמור על כיוון התנועה לצדדים. החליקו באלכסון קדימה ושמאלה או ימינה כדי לבחור את צד הנחיתה, גם לקצה הנגדי של השולחן."))
            Text(t("Beginner, Starter, Standard and Pro", "מתחילים, נינוחה, רגילה ומקצועני")).font(.title2.bold())
            // Android guide_intro (96ae066).
            Text(t("Beginner hits automatically when your paddle is in place. Starter gives you more time to prepare an aimed swipe. Standard needs closer timing. Pro adds precise swipes and spin. House players have their own power, forehand, backhand and serve skills.", "במתחילים המחבט חובט אוטומטית כשהוא במקום. בנינוחה יש יותר זמן להכין החלקה מכוונת. ברגילה צריך תזמון מדויק יותר. במקצועני מוסיפים החלקות מדויקות וסיבוב. לכל שחקן בית כישורים משלו בעוצמה, בכף יד, בגב יד ובהגשה."))
            if model.experience.online {
                Text(t("Play together", "משחקים יחד")).font(.title2.bold())
                Text(t("Create a friendly game or tournament, copy its code and share it. Add house players or let friends join. Both human players tap Ready. Only one final result is saved, and tournament standings update for everyone. You can keep three open games and three open tournaments.", "צרו משחק ידידות או טורניר, העתיקו את הקוד ושתפו אותו. הוסיפו שחקני בית או הזמינו חברים. שני השחקנים נוגעים במוכנים. נשמרת תוצאה סופית אחת וטבלת הטורניר מתעדכנת אצל כולם. אפשר לשמור שלושה משחקים ושלושה טורנירים פתוחים."))
                Text(t("Return to an unfinished match after an interruption. Rooms are removed after two weeks without activity from any participant.", "אפשר לחזור למשחק שלא הסתיים לאחר הפרעה. חדרים נמחקים לאחר שבועיים ללא פעילות של אף משתתף."))
            }
        }.padding(24) }.navigationTitle(t("How to play", "איך משחקים")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { backButton { showHelp = false } } } }
    }
    private var commerceSheet: some View {
        NavigationStack { ScrollView { VStack(spacing: 18) {
            Text(commerce.isRemoveAdsActive ? t("Ads are removed on this Apple account.", "הפרסומות הוסרו בחשבון Apple הזה.") : t("Remove ads with a one-time App Store purchase.", "הסירו פרסומות ברכישה חד־פעמית ב־App Store.")).multilineTextAlignment(.center)
            if !commerce.isRemoveAdsActive {
                action(t("Remove ads", "הסרת פרסומות") + (commerce.removeAdsProduct.map { " · " + $0.displayPrice } ?? ""), color: MPStyle.mint) { Task { await commerce.purchaseRemoveAds() } }.disabled(commerce.removeAdsProduct == nil || commerce.isBusy)
                if commerce.removeAdsProduct == nil { Text(t("The App Store product is currently unavailable. Please try again later.", "המוצר אינו זמין כרגע ב־App Store. נסו שוב מאוחר יותר.")).font(.callout) }
            }
            action(t("Restore purchases", "שחזור רכישות")) { Task { await commerce.restorePurchases() } }.disabled(commerce.isBusy)
            action(t("Redeem App Store code", "מימוש קוד App Store"), color: MPStyle.lilac) { showCommerce = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { redeem = true } }
            if commerce.status == .pending { Text(t("Waiting for purchase approval.", "ממתינים לאישור הרכישה.")) }
            if commerce.status == .failed { Text(t("The purchase could not be completed. Your entitlement has not been changed.", "לא ניתן היה להשלים את הרכישה. הזכאות שלכם לא שונתה.")) }
        }.padding(24) }.navigationTitle(t("Remove ads", "הסרת פרסומות")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { backButton { showCommerce = false } } } }
        // The grown-up gate uses a medium sheet; the unlocked options use the full height.
        .presentationDetents([.large])
    }
}

/// A row of large choice buttons whose chosen option is unmistakable: filled pink, bold white text and a check
/// mark. It replaces the system segmented picker, whose selection could not be seen on iPad (owner report 2026-10).
struct MPChoiceBar<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let chosen = option.value == selection
                Button { selection = option.value } label: {
                    HStack(spacing: 6) {
                        if chosen { Image(systemName: "checkmark.circle.fill") }
                        Text(option.label).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(chosen ? Color.white : MPStyle.ink)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(chosen ? MPStyle.pink : Color.white, in: Capsule())
                    .overlay { Capsule().strokeBorder(chosen ? MPStyle.pink : MPStyle.ink.opacity(0.25), lineWidth: 2) }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

enum MPStyle {
    static let mint = Color(red: 185 / 255, green: 244 / 255, blue: 220 / 255)
    static let blue = Color(red: 184 / 255, green: 217 / 255, blue: 1)
    static let lilac = Color(red: 232 / 255, green: 220 / 255, blue: 1)
    static let ink = Color(red: 40 / 255, green: 45 / 255, blue: 78 / 255)
    static let pink = Color(red: 233 / 255, green: 30 / 255, blue: 99 / 255)
    static let bar = Color(red: 48 / 255, green: 72 / 255, blue: 99 / 255)
    /// Android FamilyMenu.ADVANCED.
    static let yellow = Color(red: 1, green: 0xe0 / 255, blue: 0x82 / 255)
    /// Android PlayActivity footer links: pale blue over the dark sections and the setting.
    static let link = Color(red: 0xc0 / 255, green: 0xe7 / 255, blue: 1)
}

/// Android FamilyMenu.section with Ping Pong's quiet gray-to-navy panel and white heading (2026-10). The open or
/// closed choice is remembered.
struct MPMenuSection<Content: View>: View {
    let id: String
    let title: String
    let openByDefault: Bool
    @ViewBuilder let content: Content
    @State private var open: Bool?
    private var key: String { "modern.pong.menu.section." + id }
    var body: some View {
        let isOpen = open ?? ((UserDefaults.standard.object(forKey: key) as? Bool) ?? openByDefault)
        VStack(spacing: 6) {
            Button {
                let next = !isOpen
                open = next; UserDefaults.standard.set(next, forKey: key)
            } label: {
                HStack {
                    Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Text(isOpen ? "−" : "+").font(.system(size: 26, weight: .bold)).foregroundStyle(.white).frame(width: 42, height: 48)
                }.padding(.horizontal, 6).frame(minHeight: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(title + (isOpen ? ", −" : ", +"))
            if isOpen { content }
        }
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, isOpen ? 10 : 4)
        .background(LinearGradient(colors: [Color(red: 0x3c / 255, green: 0x46 / 255, blue: 0x51 / 255), Color(red: 0x2e / 255, green: 0x3c / 255, blue: 0x4d / 255), Color(red: 0x22 / 255, green: 0x33 / 255, blue: 0x48 / 255)],
                                   startPoint: .top, endPoint: .bottom).opacity(0xf0 / 255), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(red: 0x5f / 255, green: 0x72 / 255, blue: 0x85 / 255).opacity(0x66 / 255), lineWidth: 1))
    }
}

struct MPRosterRow { let id: String; let participant: MPParticipant }

/// Android `tournament_remove`: the supplied red X (a drawn X where the art is not bundled).
struct MPRemoveMark: View {
    private static let art = MPArtFiles.image("tournament_remove.webp")
    var body: some View {
        if let image = MPRemoveMark.art { Image(uiImage: image).resizable().scaledToFit().padding(12) }
        else { Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(MPStyle.pink) }
    }
}
struct MPAvatar: View {
    let character: String; let icon: Int
    /// Android c9f5fa6 `BotPortrait.championRank`: a Champion's portrait wears its colour (-1: as authored).
    var championRank = -1
    var body: some View {
        Group {
            if MPRoster.find(character) != nil, let pose = MPPoseAtlas.portrait(character, championRank: championRank) { Image(uiImage: pose).resizable().scaledToFit().padding(.vertical, 2) }
            else if character == "minik" { Image("mp_minik_motion_ready").resizable().scaledToFit() }
            else if let image = Self.image(character) { Image(uiImage: image).resizable().scaledToFit() }
            else { Text(MPNames.icons[max(0, icon) % MPNames.icons.count]).font(.system(size: 48)) }
        }.accessibilityHidden(true)
    }
    private static var cache: [String: UIImage] = [:]
    private static func image(_ id: String) -> UIImage? {
        if let value = cache[id] { return value }
        guard !id.isEmpty, MPRoster.find(id) != nil, let cg = UIImage(named: "mp_bot_" + id)?.cgImage,
            let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(cg.width / 4), height: CGFloat(cg.height / 2))) else { return nil }
        let value = UIImage(cgImage: cropped); cache[id] = value; return value
    }
}

/// Android `ArenaBackdrop` behind a match (LocalizedActivity.safeContent(arena:)): the arena's scenery aspect-filled, the
/// Beach shoreline kept above the far baseline in landscape, and a dark top gradient so the white captions stay legible.
/// Only Minik Ping Pong bundles the art; elsewhere (and for Indoors) the original setting is used.
struct MPArenaPageBackdrop: View {
    let arena: MPArena
    private static var cache: [String: UIImage] = [:]
    static func image(_ arena: MPArena, wide: Bool) -> UIImage? {
        guard let file = arena.backdropFile(wide: wide) else { return nil }
        if let image = cache[file] { return image }
        let image = arena.backdrop(wide: wide); if let image { cache = [file: image] }; return image
    }
    static func available(_ arena: MPArena) -> Bool { arena.backdropFile(wide: false).flatMap(MPArtFiles.url) != nil }
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size, wide = size.width > size.height
            ZStack(alignment: .topLeading) {
                MPIllustratedBackground()
                if let image = Self.image(arena, wide: wide), image.size.width > 0, image.size.height > 0 {
                    // The same placement as the court's own scenery (MPSinglesArena.destination), so both line up.
                    let rect = MPSinglesArena.destination(image.size, in: size, arena: arena)
                    Image(uiImage: image).resizable().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                }
                LinearGradient(colors: [MPColor.color(0x9c10243b), .clear], startPoint: .top, endPoint: .bottom).frame(width: size.width, height: size.height * 0.25)
            }.frame(width: size.width, height: size.height).clipped()
        }.accessibilityHidden(true)
    }
}

/// Large choice buttons in a grid (two or four columns) for the longer Android selector lists (arenas, controls); the
/// chosen one is filled pink with a check mark, like `MPChoiceBar`.
struct MPChoiceGrid<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var columns = 2
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, min(columns, options.count))), spacing: 8) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index], chosen = option.value == selection
                Button { selection = option.value } label: {
                    HStack(spacing: 6) {
                        if chosen { Image(systemName: "checkmark.circle.fill") }
                        Text(option.label).lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                    }
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(chosen ? Color.white : MPStyle.ink)
                    .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 50)
                    .background(chosen ? MPStyle.pink : Color.white, in: Capsule())
                    .overlay { Capsule().strokeBorder(chosen ? MPStyle.pink : MPStyle.ink.opacity(0.25), lineWidth: 2) }
                    .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selection)
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

/// Android LocalizedActivity.safeContent(illustrated = true): a night-to-sand gradient under modern_surround,
/// filling the whole screen (aspect fill instead of Android's stretch, so the art keeps its proportions).
struct MPIllustratedBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 17 / 255, green: 29 / 255, blue: 57 / 255),
                                        Color(red: 29 / 255, green: 71 / 255, blue: 86 / 255),
                                        Color(red: 218 / 255, green: 182 / 255, blue: 119 / 255)],
                               startPoint: .top, endPoint: .bottom)
                Image("mp_modern_surround").resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Android c9f5fa6 (`center = false`): an explanation reads from the start edge of its card.
    func leadingText() -> some View { multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true) }
}
