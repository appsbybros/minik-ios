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
    var body: some View {
        ZStack {
            MPIllustratedBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                header
                switch model.route {
                case .menu: menu
                case .lobby: lobby
                case .game: game
                case .guide: guide
                case .result: result
                }
            }
        }
        .overlay {
            // Android VictoryConfetti: brief and noninteractive; a new celebration restarts it.
            if let celebration = model.celebration { MPVictoryConfetti().id(celebration) }
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
        .alert(t("Please try again", "נסו שוב"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(t("OK", "אישור")) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $showHelp) { help }
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
        }
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
                action(t("Learn how to play with Minik", "למדו לשחק עם מיניק"), color: MPStyle.mint) { model.guide() }
                if model.experience.profiles {
                    action(model.identity?.name ?? t("Nickname & avatar", "כינוי ודמות"), color: MPStyle.mint) {
                        if !expanded.contains("profile") { avatarIndex = model.identity?.avatar ?? 0; avatarCharacter = model.identity?.characterId ?? "miniko" }
                        toggle("profile")
                    }
                    if expanded.contains("profile") { profileEditor }
                    action(t("New friendly game", "משחק ידידות חדש"), color: MPStyle.blue) { toggle("friendly") }
                    if expanded.contains("friendly") { friendlyForm }
                    action(t("New tournament", "טורניר חדש"), color: MPStyle.blue) { toggle("tournament") }
                    if expanded.contains("tournament") { tournamentForm }
                    roomSection(.friendly)
                    roomSection(.tournament)
                    if model.online {
                        if model.connecting { ProgressView(t("Connecting…", "מתחברים…")) }
                        else if !model.connected {
                            // Starting offline shows this note instead of a dialog (owner report 2026-10).
                            Text(t("Online play isn't available right now. You can still play with the house players.", "המשחק המקוון אינו זמין כרגע. אפשר לשחק עם שחקני הבית.")).font(.callout).multilineTextAlignment(.center)
                            Button(t("Retry online connection", "נסו להתחבר שוב")) { Task { await model.retryOnline(removeAds: commerce.isRemoveAdsActive) } }.font(.headline).padding(12)
                        }
                        HStack {
                            TextField(t("Enter code", "הזינו קוד"), text: $joinCode).textInputAutocapitalization(.characters).autocorrectionDisabled().font(.title3.bold()).textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight)
                            Button(t("Join", "הצטרפו")) { Task { await model.join(joinCode) } }.font(.headline).padding(14).background(MPStyle.blue, in: RoundedRectangle(cornerRadius: 14)).disabled(!model.connected || model.busy)
                        }.padding(.top, 8)
                    }
                    // Android PlayActivity (Advanced): "More Minik apps & games" as a link, behind the family grown-up gate.
                    familyLink(FamilyMessages.text("More Minik apps & games", "עוד אפליקציות ומשחקי מיניק")) { FamilyMessages.shared.showMoreApps(gate: nil) }
                    action(commerce.isRemoveAdsActive ? t("Parents / adults · Ads removed", "להורים ולמבוגרים · הפרסומות הוסרו") : t("Parents / adults · Remove ads", "להורים ולמבוגרים · הסרת פרסומות"), color: MPStyle.mint) { commerceUnlocked = false; showCommerce = true }
                } else {
                    controls
                    carousel
                    action(t("Start", "התחלת משחק"), color: MPStyle.blue) { model.startSingle() }
                }
                if model.busy { ProgressView().accessibilityLabel(t("Loading", "טוען")) }
            }.frame(maxWidth: 560).padding(.horizontal, 20).padding(.bottom, 28).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
    }
    private func toggle(_ key: String) { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } }
    /// Android `FamilyMenu.link` with no background: bold, underlined, family blue.
    private func familyLink(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(size: 17, weight: .bold)).underline().foregroundStyle(Color(red: 0x28 / 255, green: 0x69 / 255, blue: 0xbd / 255))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
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
    private func action(_ title: String, color: Color = MPStyle.blue, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.system(.headline, design: .rounded, weight: .bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 64).padding(.horizontal, 8) }
            .buttonStyle(.plain).background(color, in: RoundedRectangle(cornerRadius: 18)).disabled(model.busy)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: gap, content: content).padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
    }
    private var controls: some View {
        VStack(spacing: 14) {
            Text(t("Control difficulty", "רמת השליטה")).font(.headline)
            // Owner report 2026-10: the system segmented picker showed no selection on iPad.
            MPChoiceBar(title: t("Control difficulty", "רמת השליטה"),
                        options: [(value: MPLevel.beginner, label: t("Beginner", "מתחילים")),
                                  (value: MPLevel.easy, label: t("Standard", "רגילה")),
                                  (value: MPLevel.superHard, label: t("Pro", "מקצוענים"))],
                        selection: $model.level)
                .onChange(of: model.level) { _, _ in model.saveControls() }
            Text(controlHint).font(.callout).multilineTextAlignment(.center)
            HStack { Text(t("Points to win", "נקודות לניצחון")).font(.headline); Spacer(); Picker(t("Points", "נקודות"), selection: $model.target) { ForEach(model.level.targets, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu).font(.title3.bold()) }
        }
    }
    private var controlHint: String {
        // Android PlayActivity control description (2026-10), one sentence per selected level.
        if model.level.automaticContact { return t("Beginner: move into place for an automatic hit; a small sideways swipe aims it. Opponent skill comes from your chosen house player.", "מתחילים: מזיזים את המחבט למקום לחבטה אוטומטית; החלקה קטנה הצידה מכוונת אותה. יכולת היריב נקבעת לפי שחקן הבית שתבחרו.") }
        return model.level.pro ? t("Pro: precise timing and power. Opponent skill comes from your chosen house player.", "מקצועני: תזמון ועוצמה מדויקים. יכולת היריב נקבעת לפי שחקן הבית שתבחרו.") : t("Standard: tap or swipe; faster swipes add power. Opponent skill comes from your chosen house player.", "רגילה: מקישים או מחליקים; החלקה מהירה מוסיפה עוצמה. יכולת היריב נקבעת לפי שחקן הבית שתבחרו.")
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
    private var friendlyForm: some View {
        card {
            controls; carousel
            action(t("Start", "התחלת משחק")) { Task { await model.create(.friendly, house: model.selectedPlayer) } }
            if model.online { action(t("Invite a friend by code", "הזמינו חבר באמצעות קוד"), color: MPStyle.lilac) { Task { await model.create(.friendly, house: nil) } }.disabled(!model.connected) }
        }
    }
    private var tournamentForm: some View {
        card {
            // Android PlayActivity "Tournament format": round robin, or a knockout redrawn each round (2…9 players).
            Text(t("Tournament format", "שיטת הטורניר")).font(.headline)
            MPChoiceBar(title: t("Tournament format", "שיטת הטורניר"),
                        options: MPTournamentFormat.allCases.map { (value: $0, label: $0.title(he)) },
                        selection: $tournamentFormat)
                .onChange(of: tournamentFormat) { _, value in model.preferences.knockoutFormat = value == .knockout }
            if tournamentFormat == .knockout {
                Stepper(t("Players: \(knockoutCapacity)", "שחקנים: \(knockoutCapacity)"), value: $knockoutCapacity, in: 2...MPKnockout.maxPlayers).font(.headline)
                Text(t("Pairs are drawn again each round. With an odd number of players, one randomly chosen player advances without playing. Win to stay in!", "בכל סיבוב מוגרלים זוגות מחדש. כשמספר השחקנים אי־זוגי, שחקן אחד נבחר באקראי ועולה בלי לשחק. מנצחים וממשיכים!")).font(.callout).multilineTextAlignment(.center)
            } else {
                Stepper(t("Players: \(capacity)", "שחקנים: \(capacity)"), value: $capacity, in: 2...8).font(.headline)
                MPChoiceBar(title: t("Rounds", "סבבים"),
                            options: [(value: 1, label: t("One round", "סבב אחד")), (value: 2, label: t("Two rounds", "שני סבבים"))],
                            selection: $legs)
                Stepper(t("Standings points per win: \(winPoints)", "נקודות בטבלה לכל ניצחון: \(winPoints)"), value: $winPoints, in: 1...5).font(.headline)
            }
            controls
            Text(t("Add house players and invite friends using the same code.", "הוסיפו שחקני בית והזמינו חברים באמצעות אותו קוד.")).font(.callout).multilineTextAlignment(.center)
            action(t("Create tournament", "יצירת טורניר")) {
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
            HStack {
                Button { nicknameIndex = (nicknameIndex + 99) % 100 } label: { Image(systemName: "chevron.left.circle.fill").font(.title).frame(width: 44, height: 48) }
                Text(MPNames.candidate(nicknameIndex, hebrew: he, character: avatarCharacter)).font(.headline).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                Button { nicknameIndex = (nicknameIndex + 1) % 100 } label: { Image(systemName: "chevron.right.circle.fill").font(.title).frame(width: 44, height: 48) }
            }.environment(\.layoutDirection, .leftToRight)
            action(t("Save nickname & avatar", "שמירת כינוי ודמות"), color: MPStyle.mint) { Task { await model.profile(index: nicknameIndex, avatar: avatarIndex, character: avatarCharacter); if model.error == nil { expanded.remove("profile") } } }.disabled(!model.connected)
        }
    }
    private func roomSection(_ kind: MPSessionKind) -> some View {
        let key = kind.path, open = expanded.contains(key), rooms = model.rooms.filter { $0.kind == kind }
        return VStack(spacing: open ? gap : 0) {
            Button { toggle(key) } label: {
                HStack { Text(kind == .friendly ? t("Your games", "המשחקים שלכם") : t("Your tournaments", "הטורנירים שלכם")).font(.headline.bold()); Spacer(); Text(open ? "−" : "+").font(.system(size: 36, weight: .heavy)).frame(width: 44, height: 48) }
                    .padding(.horizontal, 18).frame(height: 64)
            }.buttonStyle(.plain).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 18))
            if open {
                if rooms.isEmpty { Text(t("Nothing here yet", "עדיין אין כאן משחקים")).padding(12) }
                ForEach(rooms) { s in
                    Button { model.enter(s) } label: {
                        VStack(spacing: 6) { Text((kind == .friendly ? t("Friendly game", "משחק ידידות") : t("Tournament", "טורניר")) + " (\(s.code))").font(.headline); Text(s.complete ? t("Finished", "הסתיים") : t("Continue", "המשך")).font(.callout) }.frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.plain).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.padding(open ? 8 : 0).background(open ? MPStyle.lilac.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 20))
    }
    private var lobby: some View {
        ScrollView {
            if let s = model.session {
                VStack(spacing: gap) {
                    if model.online && !s.complete {
                        Button { UIPasteboard.general.string = s.code; copied = true } label: { Label(s.code, systemImage: "doc.on.doc").font(.title2.bold()).padding(14).frame(maxWidth: .infinity) }.background(MPStyle.blue, in: RoundedRectangle(cornerRadius: 16)).environment(\.layoutDirection, .leftToRight)
                        Text(copied ? t("Code copied", "הקוד הועתק") : t("Tap to copy and share this code with a friend.", "געו להעתקת הקוד ושתפו אותו עם חבר.")).font(.callout)
                    }
                    // Android renderRoom: every room shows its control level.
                    Text(t("Controls: ", "רמת השליטה: ") + MPControlChoice.title(s.difficulty, hebrew: he)).font(.callout.bold())
                    if s.complete { completedRoom(s) } else { openRoom(s) }
                }.frame(maxWidth: 720).padding(20).frame(maxWidth: .infinity)
            }
        }
    }
    /// Android PlayActivity.completed: the result headline and Done; a completed room is not kept in history.
    @ViewBuilder private func completedRoom(_ s: MPSession) -> some View {
        card {
            Text(MPCompletionText.headline(s, model.userID, hebrew: he)).font(.title2.bold()).multilineTextAlignment(.center)
            action(t("Done", "סיום"), color: MPStyle.mint) { model.dismissCompleted() }
        }
        if s.kind == .friendly { ForEach(s.matches.values.sorted { $0.id < $1.id }) { fixtureRow(s, $0, interactive: false) } }
        else if s.knockout { bracket(s) }
        else { standings(s) }
    }
    @ViewBuilder private func openRoom(_ s: MPSession) -> some View {
        if s.knockout { knockoutSummary(s) }
        else if s.kind == .tournament { standings(s) }
        else { friendlyParticipants(s) }
        if s.state == "WAITING" && s.host == model.userID {
            if s.participants.count < s.capacity {
                Text(t("Add a house player, or let a friend join using the code.", "הוסיפו שחקן בית, או הזמינו חבר באמצעות הקוד.")).multilineTextAlignment(.center)
                carousel
                action(t("Add \(model.selectedPlayer.name(hebrew: he))", "הוסיפו את \(model.selectedPlayer.name(hebrew: he))")) { Task { await model.addHouse(model.selectedPlayer) } }
                    .disabled(s.participants.values.contains { $0.bot?.characterId == model.selectedPlayer.id })
            }
            if s.kind == .tournament {
                ForEach(s.roster.filter { s.participants[$0]?.bot != nil }, id: \.self) { id in
                    let name = s.participants[id]?.name(hebrew: he) ?? ""
                    action(t("Remove \(name)", "הסרת \(name)"), color: MPStyle.lilac) { Task { await model.removeHouse(id) } }
                }
            }
            if s.participants.count == s.capacity { action(s.kind == .tournament ? t("Start tournament", "התחלת הטורניר") : t("Continue", "המשך")) { Task { await model.startTournament() } } }
        }
        let mine = s.matches.values.filter { $0.contains(model.userID) && !$0.terminal }.sorted { $0.id < $1.id }
        if s.knockout {
            if s.state != "WAITING" {
                // Android: the knockout shows the player's own status, their match and the redrawn bracket.
                card { Text(MPKnockout.playerStatus(s, model.userID, hebrew: he)).font(.headline).multilineTextAlignment(.center) }
                ForEach(mine) { match in fixtureRow(s, match) }
                bracket(s)
            }
        } else {
            if s.kind == .tournament && !s.matches.isEmpty {
                if mine.isEmpty { Text(t("Your matches are complete. Waiting for the other players to finish the tournament.", "המשחקים שלכם הסתיימו. ממתינים לשאר השחקנים לסיום הטורניר.")).multilineTextAlignment(.center) }
                else { Text(t("Your next games", "המשחקים הבאים שלכם")).font(.title3.bold()) }
            }
            ForEach(mine) { match in fixtureRow(s, match) }
            if s.kind == .tournament && !s.matches.isEmpty {
                Button { toggle("allMatches") } label: { HStack { Text(t("All matches", "כל המשחקים")).font(.headline); Spacer(); Text(expanded.contains("allMatches") ? "−" : "+").font(.largeTitle.bold()) }.padding(16) }.buttonStyle(.plain).background(MPStyle.lilac, in: RoundedRectangle(cornerRadius: 18))
                if expanded.contains("allMatches") { ForEach(s.matches.values.sorted { $0.id < $1.id }) { fixtureRow(s, $0, interactive: false) } }
            }
            if s.kind == .friendly { ForEach(s.matches.values.filter { $0.terminal }.sorted { $0.id < $1.id }) { fixtureRow(s, $0, interactive: false) } }
        }
        if s.kind == .tournament {
            let delete = MPRules.canDelete(s, actor: model.userID)
            action(delete ? t("Delete tournament", "מחיקת הטורניר") : t("Leave tournament", "עזיבת הטורניר"), color: MPStyle.lilac) { Task { await model.leave(delete: delete) } }
        } else if MPRules.canFinishFriendly(s, actor: model.userID) {
            action(t("Close game", "סגירת המשחק"), color: MPStyle.lilac) { Task { await model.leave(delete: true) } }
        }
    }
    /// Android PlayActivity.tournament (knockout): the roster before the start, then the round's remaining matches and stage.
    @ViewBuilder private func knockoutSummary(_ s: MPSession) -> some View {
        if s.state == "WAITING" {
            card {
                Text(MPMatchText.ordered("\(s.participants.count) / \(s.capacity)") + t(" players", " שחקנים")).font(.headline)
                Text(t("Players · Knockout", "שחקנים · נוקאאוט")).font(.title3.bold())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(s.roster, id: \.self) { id in
                        if let p = s.participants[id] {
                            VStack(spacing: 6) {
                                MPAvatar(character: p.identity.characterId, icon: p.identity.avatar).frame(height: 66)
                                Text(p.name(hebrew: he)).font(.caption.bold()).lineLimit(2).multilineTextAlignment(.center)
                            }
                        }
                    }
                }
            }
        } else {
            let remaining = MPKnockout.matches(s, MPKnockout.current(s)).filter { !$0.terminal }.count
            card {
                Text(t("Matches remaining this round: \(remaining)", "משחקים שנותרו בסיבוב הזה: \(remaining)")).font(.headline).multilineTextAlignment(.center)
                Text(MPKnockout.stage(s, hebrew: he)).font(.title2.bold())
            }
        }
    }
    /// Android KnockoutBracketView inside a sideways scroll; Hebrew starts at the right-hand end.
    private func bracket(_ s: MPSession) -> some View {
        card {
            Text(s.complete ? t("Tournament bracket", "עץ הטורניר") : MPKnockout.stage(s, hebrew: he)).font(.title2.bold())
            Text(t("Swipe sideways to follow the bracket. Pairs are drawn again each round.", "החליקו לצדדים לצפייה בעץ. הזוגות מוגרלים מחדש בכל סיבוב.")).font(.caption).multilineTextAlignment(.center)
            ScrollView(.horizontal) { MPKnockoutBracketView(session: s, hebrew: he) }
                .defaultScrollAnchor(he ? UnitPoint.trailing : UnitPoint.leading)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
    private func friendlyParticipants(_ s: MPSession) -> some View {
        HStack(spacing: 24) {
            ForEach(s.roster, id: \.self) { id in if let p = s.participants[id] {
                VStack(spacing: 12) { MPAvatar(character: p.identity.characterId, icon: p.identity.avatar).frame(height: 120); Text(p.name(hebrew: he)).font(.headline).multilineTextAlignment(.center); Text(s.connected(id) ? t("Connected", "מחובר") : t("Away", "לא מחובר")).font(.caption) }.frame(maxWidth: .infinity)
            } }
        }.padding(.vertical, 16)
    }
    private func standings(_ s: MPSession) -> some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 0) { Text(t("Player", "שחקן")).frame(width: 180, alignment: .leading); ForEach([t("Points", "נקודות"), t("Wins", "ניצחונות"), t("Losses", "הפסדים"), t("Played", "שוחקו"), t("Status", "מצב")], id: \.self) { Text($0).frame(width: 90) } }.font(.headline).padding(12).background(MPStyle.blue)
                ForEach(MPRules.standings(s)) { row in if let p = s.participants[row.id] {
                    HStack(spacing: 0) {
                        HStack { MPAvatar(character: p.identity.characterId, icon: p.identity.avatar).frame(width: 48, height: 48); Text(p.name(hebrew: he)).font(.headline) }.frame(width: 180, alignment: .leading)
                        ForEach([row.points, row.wins, row.losses, row.played].indices, id: \.self) { index in Text(String([row.points, row.wins, row.losses, row.played][index])).frame(width: 90) }
                        Text(s.departed[row.id] == true ? t("Left", "עזב") : s.complete ? t("Finished", "הסתיים") : s.matches.values.contains(where: { $0.phase == .playing && $0.contains(row.id) }) ? t("Playing", "משחק") : t("Waiting", "ממתין")).font(.caption).frame(width: 90)
                    }.padding(12).background(row.id == model.userID ? MPStyle.mint : .white)
                    Divider()
                } }
            }.clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    private func fixtureRow(_ s: MPSession, _ match: MPFixture, interactive: Bool = true) -> some View {
        card {
            Text([match.a, match.b].compactMap { s.participants[$0]?.name(hebrew: he) }.joined(separator: "  —  ")).font(.headline).multilineTextAlignment(.center)
            if match.phase == .finished { Text("\(match.scoreA) – \(match.scoreB)").font(.title2.bold()).environment(\.layoutDirection, .leftToRight) }
            else if match.phase == .cancelled { Text(t("Not finished", "לא הסתיים")) }
            else {
                HStack { ForEach([match.a, match.b], id: \.self) { id in if s.participants[id]?.bot == nil { Label(s.participants[id]?.name(hebrew: he) ?? "", systemImage: match.ready[id] == true ? "checkmark.circle.fill" : "circle").font(.callout) } } }
                if interactive && match.contains(model.userID) {
                    action(match.phase == .playing ? t("Continue game", "המשך המשחק") : match.ready[model.userID] == true ? t("Ready — waiting for the other player", "מוכנים — ממתינים לשחקן השני") : t("Ready", "מוכנים"), color: MPStyle.mint) { Task { await model.ready(match) } }
                }
            }
        }
    }
    private var game: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.identity?.name ?? t("You", "אתם")).lineLimit(1)
                Spacer()
                // Each score sits beside its own name. The digits are always laid out left to right, so in Hebrew
                // (your name on the right) the opponent's score comes first (owner report 2026-10).
                Text(he ? "\(model.opponentScore) : \(model.childScore)" : "\(model.childScore) : \(model.opponentScore)").font(.title.bold()).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                Spacer()
                Text(opponentName).lineLimit(1)
            }.font(.headline).padding(.horizontal, 18).padding(.vertical, 8)
            if model.session == nil {
                Button { if !model.paused { model.togglePause() }; showGameSettings = true } label: { Label(t("Settings", "הגדרות"), systemImage: "gearshape.fill").font(.headline).padding(10) }
            }
            if let scene = model.scene { SpriteView(scene: scene).accessibilityLabel(t("Ping Pong table. Tap to serve or return; swipe diagonally to aim.", "שולחן פינג פונג. נגיעה להגשה או להחזרה; החלקה באלכסון לכיוון.")).overlay(alignment: .bottom) { Text(gameStatus).font(.callout.bold()).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 8).allowsHitTesting(false) } }
        }
    }
    private var opponentName: String {
        if let s = model.session, let m = model.fixture { return s.participants[m.a == model.userID ? m.b : m.a]?.name(hebrew: he) ?? "" }; return model.selectedPlayer.name(hebrew: he)
    }
    /// Android PrivateMatchActivity status: a room match is prefixed with the knockout stage and its control level.
    private var gameStatus: String {
        // A connection problem is a status line, never a dialog over the court (owner report 2026-10).
        if let warning = model.gameWarning, !model.paused { return warning }
        let text = gameStatusText
        guard let s = model.session, !model.paused else { return text }
        return (s.knockout ? MPKnockout.stage(s, hebrew: he) + " · " : "") + MPControlChoice.title(s.difficulty, hebrew: he) + " · " + text
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
        case "SWIPE_SERVE": return t("Swipe forward through the ball to serve", "החליקו קדימה דרך הכדור כדי להגיש")
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
        guard let winner = model.pointWinner else { return text }
        return text + " · " + (winner == .child ? t("Your point!", "נקודה לכם!") : t("Point to \(opponentName)", "נקודה ל־\(opponentName)"))
    }
    private var gameSettings: some View {
        NavigationStack { ScrollView { VStack(spacing: 18) {
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
        if let scene = model.scene { SpriteView(scene: scene).clipShape(RoundedRectangle(cornerRadius: 16)).allowsHitTesting(model.tutorialPhase == .attempt) }
        else { Image("mp_minik_motion_ready").resizable().scaledToFit().frame(maxHeight: 220).accessibilityHidden(true) }
    }
    private var guideControls: some View {
        VStack(spacing: 12) {
            Text("\(model.tutorialStep.rawValue + 1) / \(MPTutorialStep.allCases.count)").font(.caption.bold())
            Text(model.tutorialStep.title(he)).font(.title3.bold()).multilineTextAlignment(.center)
            Text(model.tutorialStep.instruction(he)).font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if model.tutorialPhase == .feedback {
                Label(guideFeedback, systemImage: model.tutorialSuccess ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill").font(.headline).foregroundStyle(model.tutorialSuccess ? Color.green : MPStyle.pink)
            }
            action(t("Show me", "הראו לי"), color: MPStyle.lilac) { model.tutorialStart(demo: true) }
            action(model.tutorialPhase == .feedback ? t("Try again", "נסו שוב") : t("Try it yourself", "נסו בעצמכם"), color: MPStyle.mint) { model.tutorialStart(demo: false) }
            if model.tutorialSuccess { action(t("Next", "הבא")) { model.tutorialNext() } }
            action(t("To the game", "למשחק")) { model.guideToGame() }
            Toggle(t("Don’t show the guide automatically", "לא להציג את ההדרכה באופן אוטומטי"), isOn: $model.skipGuide).font(.callout).padding(.vertical, 8)
        }.padding(.horizontal, 4).padding(.bottom, 12)
    }
    private var guideFeedback: String {
        if model.tutorialStep == .autoReturn {
            return model.tutorialSuccess ? t("Great positioning! Your paddle hit automatically and returned the ball to Minik.", "מיקום מצוין! המחבט חבט אוטומטית והחזיר את הכדור למיניק.") :
                t("Move your paddle into the incoming ball’s path on your side. You can get there early and lift your finger; no tap timing is needed.", "הזיזו את המחבט למסלול הכדור בצד שלכם. אפשר להגיע מוקדם ולהרים את האצבע — אין צורך לתזמן הקשה.")
        }
        return model.tutorialSuccess ? t("Well done! The ball landed in the right area.", "כל הכבוד! הכדור נחת באזור הנכון.") : t("Try again. Watch the timing and where the ball lands.", "נסו שוב. שימו לב לתזמון ולמקום שבו הכדור נוחת.")
    }
    private var result: some View {
        ScrollView { VStack(spacing: 24) {
            if let result = model.result {
                Image(systemName: result.won ? "trophy.fill" : "hand.thumbsup.fill").font(.system(size: 72)).foregroundStyle(result.won ? .orange : MPStyle.pink).padding(.top, 32)
                if let s = model.session, let m = model.fixture {
                    // Android PrivateMatchActivity result dialog (2026-10): headline, players and score, one action.
                    Text(resultTitle(s, m)).font(.title.bold()).multilineTextAlignment(.center)
                    Text(MPMatchText.result(s.participants[m.a]?.name(hebrew: he) ?? "", m.scoreA, m.scoreB, s.participants[m.b]?.name(hebrew: he) ?? "")).font(.title2.bold()).multilineTextAlignment(.center)
                    let close = s.complete ? (s.knockout ? t("View bracket", "לעץ הטורניר") : t("Done", "סיום")) : t("Continue", "המשך")
                    action(close, color: MPStyle.mint) { model.closeResult() }
                } else {
                    Text(result.won ? t("You won!", "ניצחתם!") : t("Good game!", "משחק טוב!")).font(.largeTitle.bold())
                    resultScore(result)
                    // Owner report 2026-10: the match no longer ends by leaving the game; the child chooses.
                    action(t("Play again", "עוד משחק"), color: MPStyle.blue) { model.playAgain() }
                    action(t("Back", "חזרה"), color: MPStyle.mint) { model.back() }
                }
            }
        }.frame(maxWidth: 540).padding(24).frame(maxWidth: .infinity) }
    }
    /// "You 7 – 1 Minik": each score under its own name; the row follows the reading direction.
    private func resultScore(_ result: ModernPongResult) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 4) {
                Text(String(result.playerPoints)).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                Text(model.identity?.name ?? t("You", "אתם")).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity)
            Text("–").font(.system(size: 46, weight: .bold, design: .rounded))
            VStack(spacing: 4) {
                Text(String(result.opponentPoints)).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                Text(opponentName).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity)
        }
    }
    /// Android PrivateMatchActivity: the completed room's headline, a knockout advancement, or the match result.
    private func resultTitle(_ s: MPSession, _ m: MPFixture) -> String {
        if s.complete { return MPCompletionText.headline(s, model.userID, hebrew: he) }
        let won = m.winner == model.userID
        if won && s.knockout { return MPKnockout.advanceText(s, m, hebrew: he) }
        return won ? t("You won this match!", "ניצחתם במשחק!") : t("Match finished", "המשחק הסתיים")
    }
    private var help: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 22) {
            Text(t("Serve", "הגשה")).font(.title2.bold())
            Text(t("Tap any point on the table to aim your serve. The first bounce is on your side; the second is on the opponent’s side.", "געו בכל נקודה בשולחן כדי לכוון אליה את ההגשה. הקפיצה הראשונה בצד שלכם והשנייה בצד היריב."))
            Text(t("Return and aim", "החזרה וכיוון")).font(.title2.bold())
            Text(t("Tap when the ball reaches your paddle for a forgiving return that keeps its natural sideways direction. Swipe diagonally forward and left or right to choose the landing side, including a wide cross-table shot.", "געו כשהכדור מגיע למחבט כדי להחזיר בסלחנות ולשמור על כיוון התנועה לצדדים. החליקו באלכסון קדימה ושמאלה או ימינה כדי לבחור את צד הנחיתה, גם לקצה הנגדי של השולחן."))
            Text(t("Beginner, Standard and Pro", "מתחילים, שליטה רגילה ומקצוענים")).font(.title2.bold())
            Text(t("Beginner is the default: move the paddle into the ball’s path and it hits automatically. Standard allows taps and forgiving diagonal swipes. Pro requires precise swipe timing, direction and power. House players have their own power, forehand, backhand and serve skills.", "מתחילים היא ברירת המחדל: מזיזים את המחבט למסלול הכדור והוא חובט אוטומטית. שליטה רגילה מאפשרת נגיעות והחלקות אלכסוניות סלחניות. שליטת מקצוענים דורשת דיוק בתזמון, בכיוון ובעוצמה. לכל שחקן בית כישורים משלו בעוצמה, בכף יד, בגב יד ובהגשה."))
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
}
struct MPAvatar: View {
    let character: String; let icon: Int
    var body: some View {
        Group {
            if character == "minik" { Image("mp_minik_motion_ready").resizable().scaledToFit() }
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
