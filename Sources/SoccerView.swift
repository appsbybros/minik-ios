import SwiftUI

private enum SoccerActivityState: Sendable {
    case singleRound(SoccerSession)
    case languagePractice(LanguageSoccerPracticeSession)

    var currentSession: SoccerSession {
        switch self {
        case .singleRound(let session):
            return session
        case .languagePractice(let practice):
            return practice.currentSession
        }
    }

    var languageChallengePresentationIndex: Int? {
        guard case .languagePractice(let practice) = self else {
            return nil
        }
        return practice.roundNumber
    }

    mutating func selectBall(_ ballID: SoccerBallID) {
        switch self {
        case .singleRound(var session):
            session.selectBall(ballID)
            self = .singleRound(session)
        case .languagePractice(var practice):
            practice.selectBall(ballID)
            self = .languagePractice(practice)
        }
    }

    mutating func resolveShot(outcome: GameOutcome) {
        switch self {
        case .singleRound(var session):
            session.resolveShot(outcome: outcome)
            self = .singleRound(session)
        case .languagePractice(var practice):
            practice.resolveShot(outcome: outcome)
            self = .languagePractice(practice)
        }
    }

    mutating func nextAnswerChoiceTarget() {
        guard case .singleRound(var session) = self else {
            return
        }
        session.nextTarget()
        self = .singleRound(session)
    }

    mutating func prepareNextOrderedKick() {
        switch self {
        case .singleRound(var session):
            session.prepareNextKick()
            self = .singleRound(session)
        case .languagePractice(var practice):
            practice.prepareNextKick()
            self = .languagePractice(practice)
        }
    }

    @discardableResult
    mutating func advanceLanguageRound() -> Bool {
        guard case .languagePractice(var practice) = self,
              practice.advanceToNextRound() else {
            return false
        }
        self = .languagePractice(practice)
        return true
    }
}

struct SoccerView: View {
    @State private var activityState: SoccerActivityState
    @State private var shotTask: Task<Void, Never>?
    @State private var targetStartedAt = Date()
    @State private var languageAttemptTracker = LanguageOrderedTokenAttemptTracker()
    @State private var didEvaluateIntroduction = false
    @State private var showsIntroduction = false
    /// Android MathSoccerScreen (ab3e427): in Math a tap only chooses a ball and an upward
    /// swipe kicks it. The chosen ball, the ball under the finger and how far it moved, and the
    /// kick's direction and speed.
    @State private var aimedBallID: SoccerBallID?
    @State private var draggedBallID: SoccerBallID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragStartedAt: Date?
    @State private var mathShot: MathSoccerShot?
    @State private var sceneSize: CGSize = .zero
    @StateObject private var speechPlayer: LearningSpeechPlayer
    @StateObject private var interfaceSpeechPlayer: InterfaceSpeechPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    private let onComplete: () -> Void
    private let onExit: () -> Void
    private let mathActivityFamily: ActivityFamily?
    private let mathLevelID: MathCurriculumLevelID
    private let onAttempt: (ActivityAttemptData) -> Void
    private let introductionRepository: SoccerIntroductionRepository?
    /// Android MathSoccerScreen(demo = true) (dc12a5c): the hands-on example. Nothing is
    /// recorded, so it earns no points and never moves the level; only a goal ends it.
    private let isDemo: Bool

    init(
        session: SoccerSession,
        mathActivityFamily: ActivityFamily? = nil,
        mathLevelID: MathCurriculumLevelID = .m1,
        isDemo: Bool = false,
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onComplete: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {}
    ) {
        _activityState = State(initialValue: .singleRound(session))
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        _interfaceSpeechPlayer = StateObject(wrappedValue: InterfaceSpeechPlayer())
        self.mathActivityFamily = mathActivityFamily
        self.mathLevelID = mathLevelID
        self.isDemo = isDemo
        self.onAttempt = onAttempt
        self.onComplete = onComplete
        self.onExit = onExit
        self.introductionRepository = nil
    }

    init(
        languagePracticeSession: LanguageSoccerPracticeSession,
        introductionRepository: SoccerIntroductionRepository = SoccerIntroductionRepository(),
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onExit: @escaping () -> Void = {}
    ) {
        _activityState = State(initialValue: .languagePractice(languagePracticeSession))
        _speechPlayer = StateObject(wrappedValue: LearningSpeechPlayer())
        _interfaceSpeechPlayer = StateObject(wrappedValue: InterfaceSpeechPlayer())
        self.mathActivityFamily = nil
        self.mathLevelID = .m1
        self.onAttempt = onAttempt
        self.onComplete = {}
        self.onExit = onExit
        self.introductionRepository = introductionRepository
        self.isDemo = false
    }

    private var session: SoccerSession {
        activityState.currentSession
    }

    var body: some View {
        MinikPracticeScreen(
            progressLabel: isDemo ? "1 / 1" : "\(session.progressCount) / \(session.targetCount)",
            onExit: exitActivity
        ) { metrics in
            let compact = metrics.compact
            let board = SoccerBoardLayout(
                metrics: metrics,
                ballCount: session.round.answerBalls.count
            )

            MinikPracticeSurface(compact: compact) {
                VStack(spacing: board.spacing) {
                    // Android shows the example's instruction in the scoreboard's place.
                    if !isDemo {
                        scoreboardSection(compact: compact, showsTitle: board.showsTitle)
                    }

                    if board.sideBySide {
                        HStack(alignment: .center, spacing: board.spacing) {
                            fieldSection(compact: compact, board: board)

                            answerSection(compact: compact, board: board)
                                .frame(width: board.answerColumnWidth)
                        }
                    } else {
                        fieldSection(compact: compact, board: board)

                        answerSection(compact: compact, board: board)
                    }

                    if session.orderedTokenContent != nil {
                        actionSection(compact: compact)
                    }
                }
                .frame(minHeight: board.fillHeight)
            }
        }
        .overlay {
            if showsIntroduction {
                introductionOverlay
            }
        }
        .onAppear(perform: handleAppearance)
        // Android MathSoccerScreen: the instruction before the first kick, then each exercise.
        .mathReadAloud(
            instruction: mathActivityFamily != nil && session.currentTargetIndex == 0
                ? (isDemo
                    ? String(localized: "Swipe the ball marked 2 up toward the goal. Follow the moving dot!")
                    : String(localized: "Swipe a ball toward the goal to kick it. Aim as you swipe!"))
                : nil,
            exercise: mathActivityFamily == nil
                ? nil
                : MathReadAloud.exercise(session.promptRepresentations),
            id: session.currentTargetIndex
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                speechPlayer.stop()
                interfaceSpeechPlayer.stop()
            }
        }
        .onDisappear(perform: stopActivityAudioAndMotion)
    }

    private func scoreboardSection(compact: Bool, showsTitle: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            if showsTitle {
                Text(session.orderedTokenContent == nil
                    ? String(localized: "Soccer challenge")
                    : String(localized: "Build the word"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(red: 0.14, green: 0.42, blue: 0.54))
            }

            HStack(spacing: compact ? 12 : 16) {
                scorePill(
                    title: String(localized: "You"),
                    value: session.childScore,
                    tint: Color(red: 0.17, green: 0.58, blue: 0.82),
                    compact: compact
                )

                Text("vs")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.12), in: Capsule(style: .continuous))

                scorePill(
                    title: keeperTitle,
                    value: session.keeperScore,
                    tint: Color(red: 0.98, green: 0.67, blue: 0.24),
                    compact: compact
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localizedFormat(
                "Score. You %lld, %@ %lld",
                Int64(session.childScore),
                keeperTitle,
                Int64(session.keeperScore)
            ))
        }
        .frame(maxWidth: .infinity)
    }

    private func scorePill(title: String, value: Int, tint: Color, compact: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(String(value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 8 : 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.88), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func fieldSection(compact: Bool, board: SoccerBoardLayout) -> some View {
        VStack(spacing: board.fieldSpacing) {
            VStack(spacing: compact ? 8 : 10) {
                if session.orderedTokenContent != nil {
                    HStack {
                        Spacer()

                        Button(action: speakRoundCue) {
                            HStack(spacing: 8) {
                                MinikArtworkImage(name: MinikVisualAsset.speaker)
                                    .frame(width: 30, height: 30)
                                Text("Listen")
                            }
                        }
                        .buttonStyle(MinikUtilityButtonStyle())
                        .accessibilityLabel("Replay current word")
                        .accessibilityHint("Speaks the current word again")
                    }
                }

                // Android MathSoccerScreen (ab3e427): in Math a tap chooses the ball and a
                // swipe kicks it; the example shows its own instruction instead.
                if !isDemo {
                    Text(fieldInstruction)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(
                    Array(session.promptRepresentations.enumerated()),
                    id: \.offset
                ) { _, representation in
                    RepresentationView(
                        representation: representation,
                        context: .soccerPrompt
                    )
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            if session.orderedTokenContent != nil {
                constructedWordSection(compact: compact)
            }

            soccerScene(compact: compact, board: board)
                .overlay(alignment: .bottom) {
                    // The shot's result shows on the field, where the ball went.
                    if session.orderedTokenContent == nil,
                       let outcome = session.gameOutcome {
                        outcomeBanner(for: outcome)
                            .frame(maxWidth: 360)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                            .transition(.opacity)
                    }
                }
        }
        .padding(board.fieldPadding)
        .background(fieldBackground)
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 30 : 36, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.2)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 30 : 36, style: .continuous))
    }

    private func soccerScene(compact: Bool, board: SoccerBoardLayout) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            // The field takes the height the screen has left, so the goal, the keeper
            // and the ball shrink with a short field instead of spilling out of it.
            let scale = min(1, max(0.62, size.height / 260))
            let ballSize = (compact ? 60 : 68) * scale
            let restingY = size.height * 0.28
            let targetOffset = shotOffset(in: size)

            ZStack {
                goalView(width: min(size.width * 0.54, (compact ? 240 : 300) * scale))
                    .offset(y: -size.height * 0.22)

                keeperView(scale: scale)
                    .offset(y: -size.height * 0.1)
                    .offset(x: keeperOffset(in: size))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: session.gameOutcome)

                if isDemo && session.selectedBallID == nil {
                    MathSoccerDemoGuide(reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if let selectedBall = selectedBall {
                    soccerBallFace(
                        for: selectedBall,
                        diameter: ballSize,
                        selected: true
                    )
                    .frame(width: ballSize, height: ballSize)
                    .offset(
                        x: session.gameOutcome == nil ? 0 : targetOffset.width,
                        y: session.gameOutcome == nil ? restingY : targetOffset.height
                    )
                    .animation(shotAnimation, value: session.gameOutcome)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The swipe is measured on the screen, left to right, in Hebrew and Arabic too.
            .environment(\.layoutDirection, .leftToRight)
            .onAppear { sceneSize = size }
            .onChange(of: size) { _, newSize in sceneSize = newSize }
        }
        .frame(
            minHeight: board.sceneMinHeight,
            idealHeight: board.sceneMinHeight,
            maxHeight: board.sceneMaxHeight
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sceneAccessibilityLabel)
    }

    private var fieldBackground: some View {
        MinikArtworkImage(name: MinikVisualAsset.soccerField, contentMode: .fill)
            .overlay(Color.green.opacity(0.06))
    }

    private func goalView(width: CGFloat) -> some View {
        MinikArtworkImage(name: MinikVisualAsset.soccerGoal)
            .frame(width: width, height: width * 0.42)
    }

    private func keeperView(scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            MinikArtworkImage(name: MinikVisualAsset.soccerGoalie)
                .frame(width: 86 * scale, height: 98 * scale)

            Text(keeperTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.86))
        }
    }

    private func answerSection(compact: Bool, board: SoccerBoardLayout) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if session.orderedTokenContent != nil {
                Text(String(localized: "Available letters"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.16, green: 0.43, blue: 0.55))
            }

            ZStack {
                ballGrid(board: board)
                    .opacity(showsShotResult ? 0 : 1)
                    .allowsHitTesting(!showsShotResult)
                    .accessibilityHidden(showsShotResult)

                if showsShotResult, let isCorrect = session.educationalIsCorrect {
                    shotResultPanel(isCorrect: isCorrect, compact: compact)
                        .transition(.opacity)
                }
            }
            // Math keeps room for the result, so it takes the balls' place without
            // moving the field.
            .frame(
                maxWidth: .infinity,
                minHeight: session.orderedTokenContent == nil ? board.resultMinHeight : nil
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsShotResult)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Math: once the shot lands, its result takes the balls' place.
    private var showsShotResult: Bool {
        session.orderedTokenContent == nil && session.gameOutcome != nil
    }

    /// Every ball in rows of the layout's column count, each sized for the screen.
    private func ballGrid(board: SoccerBoardLayout) -> some View {
        VStack(spacing: board.ballSpacing) {
            ForEach(
                Array(ballRows(columns: board.columns).enumerated()),
                id: \.offset
            ) { _, row in
                HStack(spacing: board.ballSpacing) {
                    ForEach(row, id: \.id) { ball in
                        answerBallButton(ball, board: board)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func ballRows(columns: Int) -> [[SoccerAnswerBall]] {
        let balls = session.availableBalls
        let rowLength = max(1, columns)
        return stride(from: 0, to: balls.count, by: rowLength).map { start in
            Array(balls[start ..< min(start + rowLength, balls.count)])
        }
    }

    @ViewBuilder
    private func answerBallButton(_ ball: SoccerAnswerBall, board: SoccerBoardLayout) -> some View {
        if session.orderedTokenContent == nil {
            mathAnswerBall(ball, board: board)
        } else {
            letterBallButton(ball, board: board)
        }
    }

    private func letterBallButton(_ ball: SoccerAnswerBall, board: SoccerBoardLayout) -> some View {
        let selected = session.selectedBallID == ball.id

        return Button {
            selectOrKick(ball.id)
        } label: {
            answerChoiceFace(
                for: ball,
                diameter: board.ballFaceDiameter,
                selected: selected
            )
            .frame(width: board.ballFaceDiameter, height: board.ballFaceDiameter)
            .frame(width: board.ballDiameter, height: board.ballDiameter)
            .contentShape(Circle())
        }
        .buttonStyle(
            MinikSoccerBallStyle(
                state: selected ? .selected : .idle,
                compact: board.compact
            )
        )
        .disabled(session.selectedBallID != nil || session.gameOutcome != nil)
        .accessibilityLabel(ballAccessibilityLabel(for: ball))
        .accessibilityHint(answerBallHint(for: ball))
    }

    /// Android MathSoccerScreen (ab3e427): a Math ball is chosen by a tap and kicked by a swipe
    /// up toward the goal. It follows the finger while it is dragged. VoiceOver's activation,
    /// and its "Kick toward the middle of the goal" action, kick straight at the goal.
    private func mathAnswerBall(_ ball: SoccerAnswerBall, board: SoccerBoardLayout) -> some View {
        let aimed = aimedBallID == ball.id
        let dragged = draggedBallID == ball.id
        return answerChoiceFace(
            for: ball,
            diameter: board.ballFaceDiameter,
            selected: aimed
        )
        .frame(width: board.ballFaceDiameter, height: board.ballFaceDiameter)
        .overlay {
            if aimed {
                Circle()
                    .strokeBorder(Color(red: 1.0, green: 0.76, blue: 0.17), lineWidth: 4)
            }
        }
        .frame(width: board.ballDiameter, height: board.ballDiameter)
        .contentShape(Circle())
        .offset(dragged ? dragTranslation : .zero)
        .environment(\.layoutDirection, .leftToRight)
        .zIndex(dragged ? 1 : 0)
        .highPriorityGesture(kickGesture(for: ball.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ballAccessibilityLabel(for: ball))
        .accessibilityHint(answerBallHint(for: ball))
        .accessibilityAddTraits(aimed ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction {
            kickMathBall(ball.id, shot: .straight)
        }
        .accessibilityAction(named: Text(String(localized: "Kick toward the middle of the goal"))) {
            kickMathBall(ball.id, shot: .straight)
        }
    }

    /// One gesture for the tap and the swipe: a touch that hardly moves chooses the ball; a
    /// swipe up kicks it, aimed by its direction (as fractions of the field) and as fast as
    /// the finger moved. A swipe that does not go up only chooses the ball.
    private func kickGesture(for ballID: SoccerBallID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard mathBallsAreReady else { return }
                if draggedBallID != ballID {
                    draggedBallID = ballID
                    dragStartedAt = Date()
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                let startedAt = dragStartedAt ?? Date()
                let wasDragged = draggedBallID == ballID
                draggedBallID = nil
                dragTranslation = .zero
                dragStartedAt = nil
                guard mathBallsAreReady, wasDragged else { return }
                let distance = (value.translation.width * value.translation.width
                    + value.translation.height * value.translation.height).squareRoot()
                let field = sceneSize.width > 0 && sceneSize.height > 0
                    ? sceneSize
                    : CGSize(width: 320, height: 260)
                guard distance >= 12,
                      let shot = MathSoccerShot.make(
                          startX: 0.5,
                          startY: 0.9,
                          dx: Double(value.translation.width / field.width),
                          dy: Double(value.translation.height / field.height),
                          elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1000
                      ) else {
                    aimedBallID = ballID
                    return
                }
                kickMathBall(ballID, shot: shot)
            }
    }

    private var mathBallsAreReady: Bool {
        session.orderedTokenContent == nil
            && session.selectedBallID == nil
            && session.gameOutcome == nil
            && !session.isComplete
    }

    private var fieldInstruction: String {
        if session.orderedTokenContent != nil {
            return String(localized: "Kick the next letter")
        }
        return aimedBallID == nil
            ? String(localized: "Swipe a ball toward the goal to kick it. Aim as you swipe!")
            : String(localized: "Now swipe this ball toward the goal.")
    }

    private func kickMathBall(_ ballID: SoccerBallID, shot: MathSoccerShot) {
        guard mathBallsAreReady else { return }
        aimedBallID = nil
        draggedBallID = nil
        dragTranslation = .zero
        mathShot = shot
        selectOrKick(ballID)
    }

    /// Android: a goal needs the right answer and a kick inside the goal. Minik saves a wrong
    /// answer kicked inside the goal, and a kick aimed outside it misses.
    private func mathOutcome() -> GameOutcome {
        let shot = mathShot ?? .straight
        guard shot.isInsideGoal else { return .miss }
        return session.educationalIsCorrect == true ? .goal : .saved
    }

    /// The Math ball flies as long as the swipe asked for; the letter game keeps its spring.
    private var shotAnimation: Animation? {
        if reduceMotion { return nil }
        if session.orderedTokenContent == nil, let mathShot {
            return .easeOut(duration: Double(mathShot.durationMilliseconds) / 1000)
        }
        return .spring(response: 0.55, dampingFraction: 0.78)
    }

    /// The keeper dives toward a Math ball it saves and away from one that scores.
    private func keeperOffset(in size: CGSize) -> CGFloat {
        guard let outcome = session.gameOutcome else { return 0 }
        guard session.orderedTokenContent == nil, let mathShot else {
            return outcome == .saved ? size.width * 0.14 : 0
        }
        let aim = CGFloat(mathShot.endX - 0.5)
        switch outcome {
        case .saved:
            return min(0.35, max(-0.35, aim)) * size.width
        case .goal:
            return (aim > 0 ? -0.14 : 0.14) * size.width
        case .miss:
            return min(0.2, max(-0.2, aim)) * size.width
        }
    }

    /// Math's result in the balls' place: the feedback, and for VoiceOver a Continue
    /// button (without VoiceOver the next challenge follows by itself).
    private func shotResultPanel(isCorrect: Bool, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            MinikFeedbackBadge(isCorrect: isCorrect)
                .accessibilityLabel(feedbackAccessibilityLabel(isCorrect: isCorrect))

            if voiceOverEnabled {
                Button(action: continueAfterShot) {
                    Label(
                        session.currentTargetIndex == session.targetCount - 1
                            ? String(localized: "Done")
                            : String(localized: "Continue"),
                        systemImage: "arrow.forward"
                    )
                }
                .buttonStyle(MinikPrimaryActionStyle())
                .accessibilityHint("Moves to the next soccer challenge")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func answerChoiceFace(
        for ball: SoccerAnswerBall,
        diameter: CGFloat,
        selected: Bool
    ) -> some View {
        if session.orderedTokenContent != nil {
            ZStack {
                Circle()
                    .fill(languageLetterGradient(for: ball))
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.9), lineWidth: selected ? 4 : 2)
                    }

                ballRepresentation(for: ball, diameter: diameter)
            }
        } else {
            soccerBallFace(
                for: ball,
                diameter: diameter,
                selected: selected
            )
        }
    }

    private func languageLetterGradient(for ball: SoccerAnswerBall) -> LinearGradient {
        let index = session.availableBalls.firstIndex(where: { $0.id == ball.id }) ?? 0
        let palettes: [[Color]] = [
            [Color(red: 0.27, green: 0.82, blue: 0.84), Color(red: 0.18, green: 0.69, blue: 0.78)],
            [Color(red: 0.96, green: 0.42, blue: 0.64), Color(red: 0.86, green: 0.27, blue: 0.53)],
            [Color(red: 0.68, green: 0.43, blue: 0.91), Color(red: 0.52, green: 0.29, blue: 0.79)],
            [Color(red: 0.98, green: 0.69, blue: 0.29), Color(red: 0.94, green: 0.50, blue: 0.20)]
        ]
        return LinearGradient(
            colors: palettes[index % palettes.count],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var introductionOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("Soccer")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.36, blue: 0.78))

                    MinikArtworkImage(name: MinikVisualAsset.soccerGoalie)
                        .frame(width: 132, height: 146)

                    Text(soccerIntroductionText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.14, blue: 0.30))
                        .multilineTextAlignment(.center)

                    Button(action: dismissIntroduction) {
                        Text(String(localized: "Start"))
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(MinikYellowActionStyle())
                }
                .padding(28)
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.white.opacity(0.97))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
    }

    private var soccerIntroductionText: String {
        String(localized: "Tap letters in the correct order to kick toward the goal.\nA goal with the right letter earns you a point.\nMissing or being saved with a wrong letter gives the keeper a point.\nThe round continues until the word is complete.")
    }

    private func handleAppearance() {
        resumeInterruptedKick()
        guard !didEvaluateIntroduction else { return }
        didEvaluateIntroduction = true

        if introductionRepository?.registerPresentationIfNeeded() == true {
            showsIntroduction = true
            speechPlayer.stop()
            interfaceSpeechPlayer.speak(
                soccerIntroductionText,
                interfaceLocale: interfaceLocaleID
            )
        } else {
            speakRoundCue()
        }
    }

    private func dismissIntroduction() {
        interfaceSpeechPlayer.stop()
        showsIntroduction = false
        speakRoundCue()
    }

    /// The letter game's feedback under the board. Math shows its result in the
    /// balls' place instead (shotResultPanel).
    @ViewBuilder
    private func actionSection(compact: Bool) -> some View {
        if let educationalIsCorrect = session.educationalIsCorrect,
           let gameOutcome = session.gameOutcome {
            VStack(spacing: compact ? 14 : 16) {
                MinikFeedbackBadge(isCorrect: educationalIsCorrect)
                    .accessibilityLabel(feedbackAccessibilityLabel(isCorrect: educationalIsCorrect))

                outcomeBanner(for: gameOutcome)

                if session.isComplete {
                    roundResultBanner
                } else {
                    Text(educationalIsCorrect
                        ? String(localized: "Great kick! Get ready for the next letter.")
                        : String(localized: "That letter stays in play. Try again after the field resets."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.25, green: 0.46, blue: 0.55))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            Text(String(localized: "Tap the next letter to kick it toward the goal."))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(red: 0.31, green: 0.49, blue: 0.58))
                .frame(maxWidth: .infinity)
        }
    }

    private func outcomeBanner(for outcome: GameOutcome) -> some View {
        HStack(spacing: 12) {
            Image(systemName: outcomeSymbol(outcome))
                .font(.title3.weight(.bold))
                .foregroundStyle(outcomeColor(outcome))

            VStack(alignment: .leading, spacing: 2) {
                Text("Shot result")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.48, blue: 0.55))

                Text(outcomeLabel(outcome))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.27, blue: 0.33))
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.95, green: 0.99, blue: 1.0))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localizedFormat("Shot result, %@", outcomeLabel(outcome)))
    }

    private var roundResultBanner: some View {
        VStack(spacing: 4) {
            Text("Word complete")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(red: 0.14, green: 0.42, blue: 0.54))

            Text(localizedFormat(
                "You %lld • %@ %lld",
                Int64(session.childScore),
                keeperTitle,
                Int64(session.keeperScore)
            ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.46, blue: 0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.95, green: 0.99, blue: 1.0))
        )
        .accessibilityElement(children: .combine)
    }

    private func feedbackAccessibilityLabel(isCorrect: Bool) -> String {
        if session.orderedTokenContent != nil {
            return isCorrect
                ? String(localized: "Correct letter")
                : String(localized: "Incorrect letter, try again")
        }
        return isCorrect
            ? String(localized: "Correct answer")
            : String(localized: "Incorrect answer, try again")
    }

    private func soccerBallFace(
        for ball: SoccerAnswerBall,
        diameter: CGFloat,
        selected: Bool
    ) -> some View {
        ZStack {
            MinikArtworkImage(name: MinikVisualAsset.soccerBall)
                .scaleEffect(selected ? 1.02 : 1)

            Circle()
                .fill(Color.white.opacity(0.94))
                .frame(width: diameter * 0.62, height: diameter * 0.62)

            ballRepresentation(for: ball, diameter: diameter)
                .zIndex(2)
        }
    }

    @ViewBuilder
    private func ballRepresentation(
        for ball: SoccerAnswerBall,
        diameter: CGFloat
    ) -> some View {
        if let token = ball.orderedToken,
           let displayText = ball.orderedTokenDisplayText {
            Text(verbatim: displayText)
                .font(.system(size: diameter * 0.4, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.07, green: 0.16, blue: 0.20))
                .minimumScaleFactor(0.68)
                .lineLimit(1)
                .environment(\.layoutDirection, layoutDirection(for: token.direction))
        } else if let answerText = ballAnswerText(for: ball) {
            Text(verbatim: answerText)
                .font(.system(size: diameter * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(MathInk.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .allowsTightening(true)
                .frame(width: diameter * 0.56)
                .environment(\.layoutDirection, .leftToRight)
        } else {
            RepresentationView(
                representation: ball.representation,
                context: .soccerBall
            )
            .padding(diameter * 0.2)
        }
    }

    /// The answer a Math ball prints as dark text inside its white circle, as Android
    /// Minik Math Plus does: it shrinks to stay inside a ball of any size, where a
    /// fraction or percent bar was wider than the ball. Pictures keep
    /// RepresentationView.
    private func ballAnswerText(for ball: SoccerAnswerBall) -> String? {
        switch ball.representation {
        case .mathExpression(let expression):
            return expression.expression
        case .math(let math):
            switch math {
            case .numeral, .decimal, .fraction, .percent, .ratio:
                return math.displayText
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func layoutDirection(for direction: ContentDirection?) -> LayoutDirection {
        direction == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private func ballAccessibilityLabel(for ball: SoccerAnswerBall) -> String {
        ball.orderedToken?.speechText
            ?? ball.orderedToken?.text
            ?? ball.representation.accessibilityDescription
    }

    private func answerBallHint(for ball: SoccerAnswerBall) -> String {
        if session.selectedBallID == ball.id {
            return String(localized: "Shot in progress")
        }

        if session.selectedBallID != nil || session.gameOutcome != nil {
            return session.orderedTokenContent == nil
                ? String(localized: "Unavailable until you continue")
                : String(localized: "Unavailable while the shot finishes")
        }

        return session.orderedTokenContent == nil
            ? String(localized: "Double tap to kick this ball")
            : String(localized: "Double tap to kick this letter")
    }

    private func shotOffset(in size: CGSize) -> CGSize {
        guard let gameOutcome = session.gameOutcome else {
            return CGSize(width: 0, height: size.height * 0.28)
        }

        // Android ab3e427: the Math ball flies where the swipe aimed it.
        if session.orderedTokenContent == nil, let mathShot {
            let x = CGFloat(mathShot.endX - 0.5) * size.width
            return CGSize(width: x, height: -size.height * (gameOutcome == .saved ? 0.14 : 0.22))
        }

        switch gameOutcome {
        case .goal:
            return CGSize(width: 0, height: -size.height * 0.22)
        case .saved:
            return CGSize(width: size.width * 0.15, height: -size.height * 0.14)
        case .miss:
            return CGSize(width: size.width * 0.26, height: -size.height * 0.3)
        }
    }

    private var selectedBall: SoccerAnswerBall? {
        guard let selectedBallID = session.selectedBallID else {
            return nil
        }

        return session.round.answerBalls.first { $0.id == selectedBallID }
    }

    private var sceneAccessibilityLabel: String {
        if let outcome = session.gameOutcome {
            return localizedFormat("Soccer field. %@.", outcomeLabel(outcome))
        }

        if session.selectedBallID != nil {
            return String(localized: "Soccer field. Shot in progress.")
        }

        return String(localized: "Soccer field.")
    }

    private func simulatedOutcome() -> GameOutcome {
        switch Int.random(in: 0 ... 2) {
        case 0:
            .goal
        case 1:
            .miss
        default:
            .saved
        }
    }

    private func outcomeLabel(_ outcome: GameOutcome) -> String {
        switch outcome {
        case .goal:
            String(localized: "Goal")
        case .miss:
            // Android ab3e427 shot_wide: a Math kick misses only when it is aimed outside.
            session.orderedTokenContent == nil
                ? String(localized: "Outside the goal!")
                : String(localized: "Miss")
        case .saved:
            String(localized: "Saved")
        }
    }

    private func outcomeSymbol(_ outcome: GameOutcome) -> String {
        switch outcome {
        case .goal:
            return "sparkles"
        case .miss:
            return "arrow.up.forward.circle.fill"
        case .saved:
            return "hand.raised.fill"
        }
    }

    private func outcomeColor(_ outcome: GameOutcome) -> Color {
        switch outcome {
        case .goal:
            return Color(red: 0.18, green: 0.65, blue: 0.34)
        case .miss:
            return Color(red: 0.88, green: 0.48, blue: 0.3)
        case .saved:
            return Color(red: 0.18, green: 0.56, blue: 0.82)
        }
    }

    private func continueAfterShot() {
        let wasComplete = session.isComplete
        // The next challenge starts in silence (Math Soccer itself does not speak).
        speechPlayer.stop()
        interfaceSpeechPlayer.stop()
        if isDemo {
            // Android's example ends with its first goal; any other kick tries 1 + 1 again.
            let scored = session.gameOutcome == .goal
            mathShot = nil
            if scored {
                onComplete()
            } else {
                activityState = .singleRound(SoccerSession(round: session.round))
                targetStartedAt = Date()
            }
            return
        }
        activityState.nextAnswerChoiceTarget()
        mathShot = nil
        targetStartedAt = Date()

        if !wasComplete && session.isComplete {
            onComplete()
        }
    }

    private var keeperTitle: String {
        session.orderedTokenContent == nil
            ? String(localized: "Keeper")
            : String(localized: "Minik")
    }

    private func selectOrKick(_ ballID: SoccerBallID) {
        // One kick at a time: the balls wait while a shot flies or its result shows.
        guard session.selectedBallID == nil,
              session.gameOutcome == nil,
              !session.isComplete else {
            return
        }
        let target = session.orderedTokenContent == nil ? session.currentTarget.challenge : nil
        let languageContentItemID = session.orderedTokenContent?.contentItemID
        let languageTokenIndex = session.progressCount
        let responseDurationSeconds = Date().timeIntervalSince(targetStartedAt)
        activityState.selectBall(ballID)
        if !isDemo,
           let target,
           let correct = session.educationalIsCorrect,
           let family = mathActivityFamily,
           let attempt = ActivityAttemptData(
               itemID: ActivityItemID(rawValue: target.id.rawValue),
               attemptIndex: 1,
               result: correct ? .correct : .incorrect,
               responseDurationSeconds: Date().timeIntervalSince(targetStartedAt),
               activityFamily: family,
               mathLevelID: mathLevelID,
               skillID: target.primarySkill
           ) {
            onAttempt(attempt)
        }
        if let languageContentItemID,
           let presentationIndex = activityState.languageChallengePresentationIndex,
           session.selectedBallID == ballID,
           let correct = session.educationalIsCorrect,
           let attempt = languageAttemptTracker.makeAttempt(
               presentationIndex: presentationIndex,
               contentItemID: languageContentItemID,
               tokenIndex: languageTokenIndex,
               result: correct ? .correct : .incorrect,
               responseDurationSeconds: responseDurationSeconds,
               activityFamily: .soccer
           ) {
            onAttempt(attempt)
        }
        guard session.selectedBallID == ballID else {
            return
        }

        guard session.orderedTokenContent != nil else {
            // Math: the tap is the kick, as in Android Minik Math Plus (report 1 #4).
            kickAnswerBall(ballID)
            return
        }

        if let cue = session.selectedOrderedTokenSpeechCue {
            speechPlayer.speak(cue)
        }

        let outcome = simulatedOutcome()
        shotTask?.cancel()
        shotTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 20_000_000 : 180_000_000)
            guard !Task.isCancelled,
                  session.selectedBallID == ballID,
                  session.gameOutcome == nil else {
                return
            }
            activityState.resolveShot(outcome: outcome)

            let completedRound = session.isComplete
            try? await Task.sleep(
                nanoseconds: reduceMotion
                    ? (completedRound ? 160_000_000 : 100_000_000)
                    : (completedRound ? 1_600_000_000 : 900_000_000)
            )
            guard !Task.isCancelled else {
                return
            }

            if completedRound {
                if activityState.advanceLanguageRound() {
                    targetStartedAt = Date()
                    speakRoundCue()
                }
            } else {
                activityState.prepareNextOrderedKick()
                targetStartedAt = Date()
            }
        }
    }

    /// The chosen Math ball rests on the spot for a moment and flies at the goal; its
    /// result then takes the balls' place. Without VoiceOver the next challenge
    /// follows by itself, as in Android Minik Math Plus.
    private func kickAnswerBall(_ ballID: SoccerBallID) {
        let outcome = mathOutcome()
        let continuesAutomatically = !voiceOverEnabled
        shotTask?.cancel()
        shotTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 20_000_000 : 180_000_000)
            guard !Task.isCancelled,
                  session.selectedBallID == ballID,
                  session.gameOutcome == nil else {
                return
            }
            activityState.resolveShot(outcome: outcome)

            guard continuesAutomatically else {
                return
            }
            await continueAfterShownResult()
        }
    }

    /// Moves on once the shot's result has shown for a moment, unless something
    /// already did (Continue, or the screen closing).
    @MainActor
    private func continueAfterShownResult() async {
        let shownTargetIndex = session.currentTargetIndex
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        guard !Task.isCancelled,
              session.gameOutcome != nil,
              session.currentTargetIndex == shownTargetIndex else {
            return
        }
        continueAfterShot()
    }

    /// A Math kick whose task was cancelled when the screen went away still lands when
    /// the screen comes back, so the balls never stay locked on a chosen ball.
    private func resumeInterruptedKick() {
        guard session.orderedTokenContent == nil,
              !session.isComplete,
              session.selectedBallID != nil else {
            return
        }
        if session.gameOutcome == nil {
            activityState.resolveShot(outcome: mathOutcome())
        }
        guard !voiceOverEnabled else {
            return
        }
        shotTask?.cancel()
        shotTask = Task { @MainActor in
            await continueAfterShownResult()
        }
    }

    private func constructedWordSection(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your word")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.8))

                Text(constructedWordText)
                    .font(.system(size: compact ? 30 : 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.65)
                    .environment(\.layoutDirection, orderedContentLayoutDirection)
            }

            Spacer(minLength: 12)

            Text(verbatim: "\(session.builtTokens.count) / \(session.targetCount)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 12 : 14)
        .background(Color.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedFormat(
            "Built word, %@, %lld of %lld letters",
            constructedWordAccessibilityText,
            Int64(session.builtTokens.count),
            Int64(session.targetCount)
        ))
    }

    private var constructedWordText: String {
        guard let builtDisplayText = session.builtDisplayText,
              !builtDisplayText.isEmpty else {
            return String(repeating: "•", count: session.targetCount)
        }
        return builtDisplayText
    }

    private var constructedWordAccessibilityText: String {
        guard let builtDisplayText = session.builtDisplayText,
              !builtDisplayText.isEmpty else {
            return String(localized: "empty")
        }
        return builtDisplayText
    }

    private var orderedContentLayoutDirection: LayoutDirection {
        switch session.orderedTokenContent?.targetText.direction {
        case .rightToLeft:
            return .rightToLeft
        case .leftToRight, nil:
            return .leftToRight
        }
    }

    private func speakRoundCue() {
        guard let cue = session.orderedTokenContent?.speechCue else {
            return
        }
        speechPlayer.speak(cue)
    }

    private func exitActivity() {
        stopActivityAudioAndMotion()
        onExit()
    }

    private func stopActivityAudioAndMotion() {
        shotTask?.cancel()
        shotTask = nil
        speechPlayer.stop()
        interfaceSpeechPlayer.stop()
    }

    private func localizedFormat(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: String(localized: key), arguments: arguments)
    }
}

/// Android MathSoccerScreen's example (dc12a5c): an arrow up the middle of the field to the
/// goal, with a dot moving along it to show the swipe. It stands still with Reduce Motion.
private struct MathSoccerDemoGuide: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let start = CGPoint(x: size.width / 2, y: size.height * 0.92)
                let end = CGPoint(x: size.width / 2, y: size.height * 0.32)
                var arrow = Path()
                arrow.move(to: start)
                arrow.addLine(to: end)
                arrow.move(to: CGPoint(x: end.x - 12, y: end.y + 16))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x + 12, y: end.y + 16))
                canvas.stroke(
                    arrow,
                    with: .color(Color(red: 1.0, green: 0.85, blue: 0.35)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
                let seconds = context.date.timeIntervalSinceReferenceDate
                let phase = reduceMotion ? 0.5 : seconds.truncatingRemainder(dividingBy: 1.6) / 1.6
                let dot = CGPoint(x: start.x, y: start.y + (end.y - start.y) * CGFloat(phase))
                canvas.fill(
                    Path(ellipseIn: CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14)),
                    with: .color(.white)
                )
            }
        }
    }
}

/// How Soccer fits the screen MinikPracticeScreen gives it (report 1 #4). The balls
/// and the field are sized for that space, so the score, the field and every ball
/// show together without scrolling on iPhone and iPad in both orientations; a phone
/// in landscape, or very large text, still scrolls the whole page. A wide, short
/// screen puts the balls beside the field.
private struct SoccerBoardLayout {
    let compact: Bool
    let tablet: Bool
    let sideBySide: Bool
    let showsTitle: Bool
    let columns: Int
    let ballDiameter: CGFloat
    let spacing: CGFloat
    let ballSpacing: CGFloat
    let fieldPadding: CGFloat
    let fieldSpacing: CGFloat
    let sceneMinHeight: CGFloat
    let sceneMaxHeight: CGFloat
    let answerColumnWidth: CGFloat
    /// A phone's board fills the screen's height, so the field takes the spare room
    /// (MinikPracticeScreen already does that on iPad). nil without a known height.
    let fillHeight: CGFloat?

    /// The ball inside its white plate.
    var ballFaceDiameter: CGFloat {
        (ballDiameter * 0.84).rounded(.down)
    }

    /// MinikFeedbackBadge, which takes the balls' place after a Math kick.
    var resultMinHeight: CGFloat {
        tablet ? 126 : 106
    }

    init(metrics: MinikPracticeLayoutMetrics, ballCount: Int) {
        let tablet = metrics.isTablet
        let compact = metrics.compact
        // MinikPracticeScreen's padding and header, and MinikPracticeSurface's padding.
        let surfacePadding: CGFloat = tablet ? 36 : (compact ? 18 : 28)
        let headerHeight: CGFloat = tablet ? 60 : 44
        let panelWidth = min(
            metrics.contentMaxWidth,
            metrics.containerWidth - metrics.horizontalPadding * 2
        )
        let innerWidth = max(240, panelWidth - surfacePadding * 2)
        let knowsHeight = metrics.containerHeight > 0
        let chromeHeight = metrics.verticalPadding * 2 + headerHeight + metrics.stackSpacing + surfacePadding * 2
        let innerHeight: CGFloat = knowsHeight ? metrics.containerHeight - chromeHeight : 2_000

        let spacing: CGFloat = tablet ? 20 : (compact ? 12 : 16)
        let ballSpacing: CGFloat = tablet ? 16 : 10
        let fieldPadding: CGFloat = tablet ? 20 : (compact ? 12 : 16)
        let fieldSpacing: CGFloat = tablet ? 14 : (compact ? 8 : 12)
        let sceneMinHeight: CGFloat = tablet ? 190 : 118
        let showsTitle = innerHeight >= 540
        let sideBySide = innerWidth >= 540 && innerWidth > innerHeight

        // The score pills (and the title over them), and the field without its scene:
        // the instruction and a prompt picture of up to 96 points.
        let pillsHeight: CGFloat = compact ? 70 : 78
        let titleHeight: CGFloat = showsTitle ? (compact ? 33 : 37) : 0
        let scoreboardHeight = pillsHeight + titleHeight
        let instructionHeight: CGFloat = compact ? 30 : 32
        let fieldFixedHeight = fieldPadding * 2 + instructionHeight + 96 + fieldSpacing

        let count = max(1, ballCount)
        let columns: Int
        if count <= 3 {
            columns = count
        } else if sideBySide {
            columns = count == 4 ? 2 : 3
        } else {
            columns = count == 4 ? 4 : 3
        }
        let rows = (count + columns - 1) / columns

        let answerColumnWidth = ((innerWidth - spacing) * 0.42).rounded(.down)
        let gridWidth = sideBySide ? answerColumnWidth : innerWidth
        let widthLimit = (gridWidth - ballSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        let gridRoom: CGFloat
        if sideBySide {
            gridRoom = innerHeight - scoreboardHeight - spacing
        } else {
            gridRoom = innerHeight - scoreboardHeight - fieldFixedHeight - sceneMinHeight - spacing * 2
        }
        let heightLimit = (gridRoom - ballSpacing * CGFloat(rows - 1)) / CGFloat(rows)
        let largest: CGFloat = tablet ? 150 : 112
        let smallest: CGFloat = tablet ? 84 : 64
        // Never wider than a row allows; otherwise as big as the height allows.
        let diameter = min(widthLimit, max(smallest, min(heightLimit, largest)))

        self.compact = compact
        self.tablet = tablet
        self.sideBySide = sideBySide
        self.showsTitle = showsTitle
        self.columns = columns
        self.ballDiameter = max(44, diameter.rounded(.down))
        self.spacing = spacing
        self.ballSpacing = ballSpacing
        self.fieldPadding = fieldPadding
        self.fieldSpacing = fieldSpacing
        self.sceneMinHeight = sceneMinHeight
        self.sceneMaxHeight = tablet ? 320 : 250
        self.answerColumnWidth = answerColumnWidth
        // One point short of the screen, so rounding never makes the page scroll.
        self.fillHeight = knowsHeight && !tablet ? max(0, innerHeight - 1) : nil
    }
}
