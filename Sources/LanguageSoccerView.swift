import Foundation
import SwiftUI

private struct LanguageSoccerDragSample {
    let point: CGPoint
    let date: Date
}

/// A finished match while its result shows. Android LettersSoccerGame swaps the
/// running scores for the final score, celebrates a win with confetti and Minik,
/// and makes the keeper hop after a loss.
private struct LanguageSoccerRoundCelebration: Equatable {
    let startedAt: Date
    let childScore: Int
    let keeperScore: Int

    var childWon: Bool { childScore > keeperScore }
    var keeperWon: Bool { keeperScore > childScore }
}

/// One of the nine 24 dp stars fragment_letters_soccer keeps in the goal. The
/// offsets are the FrameLayout margins from the goal's top-left corner: its
/// children default to top-start, so all but one star sit on the left.
private struct LanguageSoccerGoalStar {
    let asset: Int
    let x: CGFloat
    let y: CGFloat
    let alignsRight: Bool
    let delay: Double
}

/// A kicked letter's ball, Android's ball1, ball2 or ball3. As on Android the
/// next letter can be kicked as soon as one is, so several balls can fly at once:
/// each has its own lifecycle and task, and its result counts in kick order.
private struct LanguageSoccerFlight: Identifiable {
    let id: UUID
    let ball: SoccerAnswerBall
    /// Worked out when the letter is kicked, against the keeper it will meet.
    let resolution: LanguageSoccerShotResolution
    /// Where the keeper is when the ball reaches it.
    let keeperXAtImpact: Double
    var lifecycle: LanguageSoccerShotLifecycle
    /// Where the ball is drawn; nil once it has landed.
    var point: CGPoint?
    var shotTask: Task<Void, Never>?
}

/// A counted shot's keeper bookkeeping (shot totals, the keeper's next move). It
/// waits until no ball is on its way, so every ball in the air meets the keeper
/// its outcome was worked out against.
private struct LanguageSoccerKeeperTally {
    let scored: Bool
    let gameContinues: Bool
    let keeperXAtImpact: Double
}

/// The keeper sprite for one frame: facing, squash and hop.
private struct LanguageSoccerKeeperPose {
    let mirrored: Bool
    let scaleX: CGFloat
    let scaleY: CGFloat
    let lift: CGFloat
}

/// SoccerIntroDialog in points: phones use fragment_letters_soccer_game_tour_dialog,
/// tablets its sw600dp twin with the sw700dp sizes. Offsets include the card's
/// 14 dp side and 18 dp top and bottom padding.
private struct LanguageSoccerIntroMetrics {
    let wide: Bool

    var titleTop: CGFloat { wide ? 78 : 48 }
    var titleSidePadding: CGFloat { wide ? 54 : 34 }
    var titleScale: CGFloat { wide ? 50.0 / 36.0 : 1 }
    var textTop: CGFloat { wide ? 27 : 25 }
    var textSideMargin: CGFloat { wide ? 49 : 34 }
    var textScale: CGFloat { wide ? 28.0 / 17.0 : 1 }
    var buttonScale: CGFloat { wide ? 2 : 1 }
    var buttonMinHeight: CGFloat { wide ? 64 : 40 }
    var buttonBottom: CGFloat { wide ? 53 : 43 }
    var goalieSize: CGSize { wide ? CGSize(width: 204, height: 233) : CGSize(width: 92, height: 105) }
    var goalieLeading: CGFloat { wide ? 37 : 21 }
    var ballSide: CGFloat { wide ? 120 : 65 }
    var ballOpacity: Double { wide ? 0.8 : 0.6 }
    var ballBottom: CGFloat { wide ? 23 : 18 }
    var ballTrailing: CGFloat { 9 }
    var bottomInset: CGFloat { 18 }
    var starBox: CGSize { wide ? CGSize(width: 162, height: 144) : CGSize(width: 80, height: 70) }
    var frameInsetX: CGFloat { 14 }
    var frameInsetY: CGFloat { 18 }
    /// Between the four short lines, and above and inside "More Information".
    var lineSpacing: CGFloat { wide ? 10 : 6 }
    var moreInformationTop: CGFloat { wide ? 24 : 14 }
    var moreInformationPadding: CGFloat { wide ? 20 : 12 }
}

struct LanguageSoccerView: View {
    @State private var practice: LanguageSoccerPracticeSession
    /// The finger: idle, or dragging one letter. A kick hands the letter its own
    /// lifecycle (`flights`) and frees the finger for the next letter at once.
    @State private var dragLifecycle = LanguageSoccerShotLifecycle()
    @State private var dragPoint: CGPoint?
    @State private var dragOffset = CGSize.zero
    @State private var lastDragSample: LanguageSoccerDragSample?
    @State private var dragVelocity = LanguageSoccerVector(dx: 0, dy: -1)
    /// Where the drag that kicked each letter began: that finger, still down,
    /// never grabs its letter again, even once a wrong letter is back in its slot
    /// (Android's per-letter `kicked` flag).
    @State private var kickingDragStarts: [SoccerBallID: CGPoint] = [:]
    /// The kicked letters, oldest first, until their result counts.
    @State private var flights: [LanguageSoccerFlight] = []
    @State private var keeperTallies: [LanguageSoccerKeeperTally] = []
    /// The last counted shot, for the field's accessibility label.
    @State private var lastSettledOutcome: GameOutcome?
    @State private var celebrationTask: Task<Void, Never>?
    @State private var targetStartedAt = Date()
    @State private var roundStartedAt = Date()
    @State private var attemptIndex = 1
    @State private var totalShots = 0
    @State private var goals = 0
    @State private var recentGoalResults: [Bool] = []
    @State private var keeperMoving: Bool
    @State private var stationaryKeeperX: Double?
    @State private var attemptTracker = LanguageOrderedTokenAttemptTracker()
    @State private var didEvaluateIntroduction = false
    @State private var showsIntroduction = false
    /// The introduction's "More Information" starts closed every time.
    @State private var showsMoreInformation = false
    @State private var introductionSecondsLeft = 44
    @State private var introductionCountdown: Task<Void, Never>?
    @State private var hasKicked = false
    @State private var goalStarsStartedAt: Date?
    @State private var roundCelebration: LanguageSoccerRoundCelebration?
    /// When "Goal" was last said (goalSpeechAllowed).
    @State private var lastGoalSpeechAt: Date?
    @StateObject private var speechPlayer = LearningSpeechPlayer()
    @StateObject private var interfaceSpeechPlayer = InterfaceSpeechPlayer()
    @StateObject private var soundPlayer = LanguageSoccerSoundPlayer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.interfaceLocaleID) private var interfaceLocaleID
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .title2) private var explainFontBase: CGFloat = 22
    @ScaledMetric(relativeTo: .largeTitle) private var introTitleFontBase: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var introTextFontBase: CGFloat = 17
    @ScaledMetric(relativeTo: .title3) private var introButtonFontBase: CGFloat = 20

    private let productionConfiguration: LanguageSoccerProductionConfiguration
    private let introductionRepository: SoccerIntroductionRepository
    private let onAttempt: (ActivityAttemptData) -> Void
    private let onMatchResolved: (LanguageSoccerMatchOutcome) -> Void
    private let onWordCompleted: () -> Void
    private let onPoolExhausted: (LanguageSoccerPoolBoundary) -> Void
    private let makeNextPracticeSession: (() -> LanguageSoccerPracticeSession?)?
    private let onExit: () -> Void

    init(
        practiceSession: LanguageSoccerPracticeSession,
        productionConfiguration: LanguageSoccerProductionConfiguration,
        introductionRepository: SoccerIntroductionRepository = SoccerIntroductionRepository(),
        onAttempt: @escaping (ActivityAttemptData) -> Void = { _ in },
        onMatchResolved: @escaping (LanguageSoccerMatchOutcome) -> Void = { _ in },
        onWordCompleted: @escaping () -> Void = {},
        onPoolExhausted: @escaping (LanguageSoccerPoolBoundary) -> Void = { _ in },
        makeNextPracticeSession: (() -> LanguageSoccerPracticeSession?)? = nil,
        onExit: @escaping () -> Void = {}
    ) {
        _practice = State(initialValue: practiceSession)
        _keeperMoving = State(initialValue: productionConfiguration.keeperTuning.initiallyMoves)
        _stationaryKeeperX = State(initialValue: nil)
        self.productionConfiguration = productionConfiguration
        self.introductionRepository = introductionRepository
        self.onAttempt = onAttempt
        self.onMatchResolved = onMatchResolved
        self.onWordCompleted = onWordCompleted
        self.onPoolExhausted = onPoolExhausted
        self.makeNextPracticeSession = makeNextPracticeSession
        self.onExit = onExit
    }

    private var session: SoccerSession { practice.currentSession }
    private var tuning: LanguageSoccerKeeperTuning { productionConfiguration.keeperTuning }
    /// Android's start and end sides follow the reading direction. The board is
    /// laid out left to right like Android's pitch, so this picks the physical side.
    private var isRightToLeft: Bool { layoutDirection == .rightToLeft }
    /// Android's start side inside the left-to-right board.
    private var startEdge: Edge.Set {
        if isRightToLeft { return .trailing }
        return .leading
    }
    private var topStartAlignment: Alignment {
        if isRightToLeft { return .topTrailing }
        return .topLeading
    }
    private var bottomStartAlignment: Alignment {
        if isRightToLeft { return .bottomTrailing }
        return .bottomLeading
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let metrics = boardMetrics(in: geometry.size)
                // The card is Android's pitch column. Where the height limits the
                // pitch it stays centred with the tie-dye around it, instead of
                // stretching into empty bands beside the pitch.
                board(metrics: metrics)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            // MaterialCardView's compat padding around the 20 dp card.
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            // Positions, the drag gesture and the keeper's facing all use physical
            // coordinates; Android's start and end items pick their side explicitly.
            .environment(\.layoutDirection, .leftToRight)

            if let roundCelebration, roundCelebration.childWon, !reduceMotion {
                LanguageSoccerConfetti(startedAt: roundCelebration.startedAt)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if showsIntroduction { introductionOverlay }
        }
        // The rainbow sky stays a background so it never sizes the stack that
        // holds the field.
        .background {
            MinikSkyBackground()
        }
        .onAppear(perform: handleAppearance)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { suspendActiveShot() }
        }
        .onDisappear(perform: stopAudioAndMotion)
    }

    /// fragment_letters_soccer's phone layout in points. `unit` turns Android's dp
    /// into points; on a larger screen the whole composition grows with the pitch
    /// and stays centred, keeping the phone proportions instead of stretching.
    private struct SoccerBoardMetrics {
        let size: CGSize
        let unit: CGFloat
        let fieldWidth: CGFloat
        let fieldFrame: CGRect
        let field: LanguageSoccerRect
        let goal: LanguageSoccerRect
        let releaseLineY: CGFloat
        let keeperSize: CGSize
        let keeperBottomY: CGFloat
        let letterDiameter: CGFloat
        let letterPitch: CGFloat
        let rowCapacity: Int
        let firstRowCenterY: CGFloat
        let shotDiameter: CGFloat
        let imageHeight: CGFloat
        let wordFontSize: CGFloat
        let builtFontSize: CGFloat
    }

    /// Android, measured against the pitch width W: the goal (mink_gate_new) is
    /// 0.815 W by 0.31 W, 14 dp below the card's top, and overlaps the pitch by
    /// 0.105 W; the pitch keeps its 713 x 1035 artwork; the release line is
    /// 0.109 W above the pitch's end; the 56 dp letters (68 dp slots) sit just
    /// below it and the player's score sits at the card's bottom. The card is
    /// the pitch plus Android's 4 dp padding on each side, so where the height
    /// limits the pitch the card narrows with it: the X, the scores, the release
    /// line, the explanation and the letter rows keep their places around the
    /// pitch. `size` is that card.
    private func boardMetrics(in available: CGSize) -> SoccerBoardMetrics {
        let availableWidth = max(1, Double(available.width))
        let height = max(1, Double(available.height))
        let fieldAspect = 1035.0 / 713.0
        let letterCount = max(1, session.round.answerBalls.count)
        // Android sizes the pitch for one row of letters, and a row holds as
        // many 68 dp slots as that pitch is wide.
        let singleRowFieldWidth = Self.fittingFieldWidth(rows: 1, availableWidth: availableWidth, height: height)
        let singleRowUnit = Self.boardUnit(forFieldWidth: singleRowFieldWidth)
        let capacity = max(1, Int(singleRowFieldWidth / (68 * singleRowUnit)))
        let rows = (letterCount + capacity - 1) / capacity
        let fieldWidth: Double
        if rows > 1 {
            fieldWidth = Self.fittingFieldWidth(rows: rows, availableWidth: availableWidth, height: height)
        } else {
            fieldWidth = singleRowFieldWidth
        }
        let unit = Self.boardUnit(forFieldWidth: fieldWidth)
        let pitch = 68 * unit
        // Never narrower than a full row of letters, should a very long word
        // have taken room from the pitch.
        let rowWidth = Double(min(capacity, letterCount)) * pitch
        let width = min(availableWidth, max(fieldWidth, rowWidth) + 8 * unit)
        let fieldHeight = fieldWidth * fieldAspect
        let goalTop = 14 * unit
        let goal = LanguageSoccerRect(
            minX: (width - fieldWidth * 0.815) / 2,
            minY: goalTop,
            width: fieldWidth * 0.815,
            height: fieldWidth * 0.31
        )
        let fieldTop = goalTop + fieldWidth * 0.205
        let fieldBottom = fieldTop + fieldHeight
        let releaseLineY = fieldBottom - fieldWidth * 0.109
        let firstRowCenterY: Double
        if rows > 1 {
            // Android's flex lines pack downward from the release line.
            firstRowCenterY = releaseLineY + pitch / 2
        } else {
            // A single flex line is centred between the pitch and the score.
            let bandTop = fieldBottom + 2 * unit
            let bandBottom = height - 81 * unit
            firstRowCenterY = bandTop + max(0, bandBottom - bandTop - pitch) / 2 + pitch / 2
        }
        let keeperScale = min(1.5, max(0.8, fieldWidth / 354))
        return SoccerBoardMetrics(
            size: CGSize(width: width, height: height),
            unit: CGFloat(unit),
            fieldWidth: CGFloat(fieldWidth),
            fieldFrame: CGRect(x: (width - fieldWidth) / 2, y: fieldTop, width: fieldWidth, height: fieldHeight),
            field: LanguageSoccerRect(minX: 0, minY: 0, width: width, height: height),
            goal: goal,
            releaseLineY: CGFloat(releaseLineY),
            keeperSize: CGSize(
                width: tuning.referenceWidth * keeperScale,
                height: tuning.referenceHeight * keeperScale
            ),
            keeperBottomY: CGFloat(goal.maxY + 5 * unit),
            letterDiameter: CGFloat(56 * unit),
            letterPitch: CGFloat(pitch),
            rowCapacity: capacity,
            firstRowCenterY: CGFloat(firstRowCenterY),
            shotDiameter: CGFloat(36 * unit),
            imageHeight: CGFloat(80 * unit),
            wordFontSize: CGFloat(fieldWidth * 0.15),
            builtFontSize: CGFloat(fieldWidth * 0.135)
        )
    }

    /// Android's dp in points: the whole composition scales with the pitch, within
    /// limits that keep the letters easy to grab.
    private static func boardUnit(forFieldWidth fieldWidth: Double) -> Double {
        min(1.5, max(0.9, fieldWidth / 354))
    }

    /// The widest pitch whose card fits the available width and whose goal, pitch
    /// and letter rows fit the height. Both needs grow with the pitch's width, so
    /// halving the range settles on it.
    private static func fittingFieldWidth(rows: Int, availableWidth: Double, height: Double) -> Double {
        var fitting = 120.0
        var tooWide = max(fitting, availableWidth)
        guard fieldFits(fitting, rows: rows, availableWidth: availableWidth, height: height) else {
            return fitting
        }
        for _ in 0 ..< 32 {
            let middle = (fitting + tooWide) / 2
            if fieldFits(middle, rows: rows, availableWidth: availableWidth, height: height) {
                fitting = middle
            } else {
                tooWide = middle
            }
        }
        return fitting
    }

    private static func fieldFits(_ fieldWidth: Double, rows: Int, availableWidth: Double, height: Double) -> Bool {
        let unit = boardUnit(forFieldWidth: fieldWidth)
        let goalAndField = 14 * unit + fieldWidth * (1035.0 / 713.0 + 0.205)
        let neededHeight = goalAndField + lettersSpaceBelowField(rows: rows, unit: unit, fieldWidth: fieldWidth)
        return fieldWidth + 8 * unit <= availableWidth && neededHeight <= height
    }

    /// The room the letters need below the pitch. One row sits centred between
    /// the pitch and the player's score. More rows pack downward from the release
    /// line, where Android's flex lines start, so they take room from the pitch
    /// only when they would run past the card's bottom.
    private static func lettersSpaceBelowField(rows: Int, unit: Double, fieldWidth: Double) -> Double {
        let singleRow = 151 * unit
        guard rows > 1 else { return singleRow }
        let packedRows = Double(rows) * 68 * unit - fieldWidth * 0.109 + 2 * unit
        return max(singleRow, packedRows)
    }

    /// The card in the rainbow-sky design (applyGameBackgrounds): the glass card with
    /// its white rim and the light wash inside it; the green pitch stays as it was.
    private func board(metrics: SoccerBoardMetrics) -> some View {
        LanguageSkyPanel(
            width: metrics.size.width,
            height: metrics.size.height,
            cornerRadius: 28 * metrics.unit,
            washed: true
        ) {
            ZStack(alignment: .topLeading) {
                boardBackdrop(metrics: metrics)
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    soccerScene(metrics: metrics, date: context.date)
                }
            }
            .frame(width: metrics.size.width, height: metrics.size.height)
            // Named on the card itself, so drag locations and positions share one origin.
            .coordinateSpace(name: "languageSoccerGame")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sceneAccessibilityLabel)
    }

    /// The pitch and the dashed release line, which Android keeps visible, on the
    /// card's light wash.
    private func boardBackdrop(metrics: SoccerBoardMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            MinikArtworkImage(name: MinikVisualAsset.soccerField)
                .frame(width: metrics.fieldFrame.width, height: metrics.fieldFrame.height)
                .position(x: metrics.fieldFrame.midX, y: metrics.fieldFrame.midY)
            releaseLineEdge(metrics: metrics, edgeOffset: 1, dashPhase: 0)
            releaseLineEdge(metrics: metrics, edgeOffset: 3, dashPhase: 5)
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .accessibilityHidden(true)
    }

    /// release_line_dash strokes the outline of a 4 dp high view with 6 dp dashes
    /// and 4 dp gaps, so its top and bottom edges are dashed out of step. The
    /// view spans the content between the card's paddings: the pitch's width.
    private func releaseLineEdge(metrics: SoccerBoardMetrics, edgeOffset: CGFloat, dashPhase: CGFloat) -> some View {
        let unit = metrics.unit
        return LanguageSoccerDashedLine()
            .stroke(
                Self.releaseLineInk,
                style: StrokeStyle(lineWidth: 2 * unit, dash: [6 * unit, 4 * unit], dashPhase: dashPhase * unit)
            )
            .frame(width: max(1, metrics.fieldFrame.width), height: 2 * unit)
            .position(x: metrics.fieldFrame.midX, y: metrics.releaseLineY + edgeOffset * unit)
    }

    private func soccerScene(metrics: SoccerBoardMetrics, date: Date) -> some View {
        let keeperMinX = keeperPosition(at: date, layout: metrics)
        return ZStack(alignment: .topLeading) {
            pitchContent(metrics: metrics, keeperMinX: keeperMinX)
            scoreLayer(metrics: metrics, date: date)
            goalArea(metrics: metrics, keeperMinX: keeperMinX, date: date)
            topControls(metrics: metrics)
            flightLayer(metrics: metrics, date: date)
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
    }

    @ViewBuilder
    private func pitchContent(metrics: SoccerBoardMetrics, keeperMinX: Double) -> some View {
        // soccerExplainText fades out for good after the first kick.
        if !hasKicked {
            explainText(metrics: metrics)
        }
        wordBlock(metrics: metrics)
        letterRow(metrics: metrics, keeperMinX: keeperMinX)
    }

    @ViewBuilder
    private func scoreLayer(metrics: SoccerBoardMetrics, date: Date) -> some View {
        if let roundCelebration {
            finalScore(roundCelebration, metrics: metrics, date: date)
        } else {
            childScoreLabel(metrics: metrics)
        }
    }

    @ViewBuilder
    private func goalArea(metrics: SoccerBoardMetrics, keeperMinX: Double, date: Date) -> some View {
        // The design's glossy candy goal (mink_gate_pretty) in place of the black
        // one, drawn to the physical goal rectangle, as Android stretches its goal,
        // so the drawn posts and crossbar match the collision posts and the keeper's
        // sweep never leaves the visible goal.
        LanguageSoccerCandyGoal()
            .frame(width: CGFloat(metrics.goal.width), height: CGFloat(metrics.goal.height))
            .position(
                x: CGFloat(metrics.goal.minX + metrics.goal.width / 2),
                y: CGFloat(metrics.goal.minY + metrics.goal.height / 2)
            )
        goalStarsLayer(metrics: metrics, date: date)
        keeperView(metrics: metrics, minX: keeperMinX, date: date)
    }

    @ViewBuilder
    private func topControls(metrics: SoccerBoardMetrics) -> some View {
        closeButton(metrics: metrics)
        if roundCelebration == nil {
            keeperScoreLabel(metrics: metrics)
        }
    }

    @ViewBuilder
    private func flightLayer(metrics: SoccerBoardMetrics, date: Date) -> some View {
        // Every kicked letter's ball, as Android flies ball1, ball2 and ball3 at once.
        ForEach(flights) { flight in
            if let point = flight.point {
                launchedBall(flight.ball, metrics: metrics)
                    .position(point)
                    .accessibilityHidden(true)
            }
        }
        if let roundCelebration, roundCelebration.childWon {
            winningMinik(roundCelebration, metrics: metrics, date: date)
        }
    }

    /// The red X at Android's end side (the left in Hebrew), 25 dp below the
    /// content's top; the tap target never drops below 44 points.
    private func closeButton(metrics: SoccerBoardMetrics) -> some View {
        let artwork = 30 * metrics.unit
        let target = max(44, artwork + 10)
        let inset = 12 * metrics.unit + artwork / 2
        return Button(action: exitActivity) {
            MinikArtworkImage(name: MinikVisualAsset.close)
                .frame(width: artwork, height: artwork)
                .frame(width: target, height: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(interfaceLocaleID.text("Home"))
        .position(
            x: isRightToLeft ? inset : metrics.size.width - inset,
            y: 35 * metrics.unit + artwork / 2
        )
    }

    /// soccerScoreMinik: the keeper's score in the top start corner.
    private func keeperScoreLabel(metrics: SoccerBoardMetrics) -> some View {
        scoreDigits(session.keeperScore, metrics: metrics)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(interfaceFormat(
                "%@ score %lld",
                interfaceLocaleID.text("Keeper"),
                Int64(session.keeperScore)
            ))
            .padding(.top, 20 * metrics.unit)
            .padding(startEdge, 14 * metrics.unit)
            .frame(
                width: metrics.size.width,
                height: metrics.size.height,
                alignment: topStartAlignment
            )
            .allowsHitTesting(false)
    }

    /// soccerScoreUser: the player's score in the bottom start corner.
    private func childScoreLabel(metrics: SoccerBoardMetrics) -> some View {
        scoreDigits(session.childScore, metrics: metrics)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(interfaceFormat(
                "%@ score %lld",
                interfaceLocaleID.text("You"),
                Int64(session.childScore)
            ))
            .padding(.bottom, 15 * metrics.unit)
            .padding(startEdge, 14 * metrics.unit)
            .frame(
                width: metrics.size.width,
                height: metrics.size.height,
                alignment: bottomStartAlignment
            )
            .allowsHitTesting(false)
    }

    /// Fredoka Medium, bold, 50 sp, in the score green.
    private func scoreDigits(_ value: Int, metrics: SoccerBoardMetrics) -> some View {
        let fontSize = 50 * metrics.unit
        return Text(verbatim: String(value))
            .font(.custom("Fredoka-Medium", fixedSize: fontSize))
            .foregroundStyle(Self.scoreGreen)
            .soccerFakeBold(Self.scoreGreen, spread: fontSize / 64)
            .lineLimit(1)
            .fixedSize()
    }

    /// endOfGameScore: the final score in two halves at the card's bottom, the
    /// player at the start, the keeper at the end and a colon between them. The
    /// winner is green, the loser pink and a tie the design's navy; the digits blink.
    private func finalScore(
        _ celebration: LanguageSoccerRoundCelebration,
        metrics: SoccerBoardMetrics,
        date: Date
    ) -> some View {
        let unit = metrics.unit
        let elapsed = date.timeIntervalSince(celebration.startedAt)
        let blinkVisible = reduceMotion || Int(max(0, elapsed) / 0.5) % 2 == 0
        let digitOpacity = blinkVisible ? 1.0 : 0.35
        let startX = isRightToLeft ? metrics.size.width * 0.75 : metrics.size.width * 0.25
        let endX = isRightToLeft ? metrics.size.width * 0.25 : metrics.size.width * 0.75
        let labelCenterY = metrics.size.height - 48 * unit
        let digitCenterY = labelCenterY - 54 * unit
        let childColor = finalScoreColor(child: true, celebration)
        let keeperColor = finalScoreColor(child: false, celebration)
        return ZStack(alignment: .topLeading) {
            finalScoreDigit(celebration.childScore, color: childColor, unit: unit)
                .opacity(digitOpacity)
                .position(x: startX, y: digitCenterY)
            finalScoreLabel(interfaceLocaleID.text("You"), color: childColor, metrics: metrics)
                .position(x: startX, y: labelCenterY)
            Text(verbatim: ":")
                .font(.system(size: 50 * unit, weight: .bold))
                .foregroundStyle(MinikPretty.navy)
                .position(x: metrics.size.width / 2, y: digitCenterY)
            finalScoreDigit(celebration.keeperScore, color: keeperColor, unit: unit)
                .opacity(digitOpacity)
                .position(x: endX, y: digitCenterY)
            finalScoreLabel(interfaceLocaleID.text("Keeper"), color: keeperColor, metrics: metrics)
                .position(x: endX, y: labelCenterY)
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(interfaceFormat(
            "Final score. You %lld, Minik %lld",
            Int64(celebration.childScore),
            Int64(celebration.keeperScore)
        ))
    }

    private func finalScoreDigit(_ value: Int, color: Color, unit: CGFloat) -> some View {
        Text(verbatim: String(value))
            .font(.system(size: 50 * unit, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private func finalScoreLabel(_ text: String, color: Color, metrics: SoccerBoardMetrics) -> some View {
        Text(text)
            .font(.system(size: 30 * metrics.unit, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: max(1, metrics.size.width / 2 - 16 * metrics.unit))
            .environment(\.layoutDirection, layoutDirection)
    }

    private func finalScoreColor(child: Bool, _ celebration: LanguageSoccerRoundCelebration) -> Color {
        if celebration.childWon {
            return child ? Self.scoreGreen : Self.scorePink
        }
        if celebration.keeperWon {
            return child ? Self.scorePink : Self.scoreGreen
        }
        return MinikPretty.navy
    }

    /// soccerExplainText: 22 sp bold black, 40 dp in from the pitch-wide content's
    /// sides, just above the word.
    private func explainText(metrics: SoccerBoardMetrics) -> some View {
        let top = CGFloat(metrics.goal.maxY) + metrics.fieldWidth * 0.06
        let bottom = CGFloat(metrics.goal.maxY) + metrics.fieldWidth * 0.35
        let height = max(1, bottom - top)
        let width = max(1, metrics.fieldWidth - 80 * metrics.unit)
        return Text(interfaceLocaleID.text("Drag and drop the letters in the right order toward the goal"))
            .font(.system(size: min(explainFontBase, 30) * metrics.unit, weight: .bold))
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.5)
            .frame(width: width, height: height, alignment: .bottom)
            .environment(\.layoutDirection, layoutDirection)
            .position(x: metrics.size.width / 2, y: top + height / 2)
            .allowsHitTesting(false)
    }

    /// soccerWordsContainer, 150 dp below the goal: the word's picture (80 dp
    /// high) when it has one, the word in black Fredoka and, under it, the letters
    /// scored so far in white. Tapping the word or picture says it again.
    @ViewBuilder
    private func wordBlock(metrics: SoccerBoardMetrics) -> some View {
        if let content = session.orderedTokenContent {
            let top = CGFloat(metrics.goal.maxY) + metrics.fieldWidth * 0.42
            let height = max(1, metrics.size.height - top)
            // builtWordText's 20 dp side margins inside the pitch-wide content.
            let maxTextWidth = max(1, metrics.fieldWidth - 40 * metrics.unit)
            VStack(spacing: 0) {
                Button(action: speakRoundCue) {
                    VStack(spacing: 10 * metrics.unit) {
                        if let image = content.image {
                            Image(image.rawValue)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: maxTextWidth, maxHeight: metrics.imageHeight)
                        }
                        targetWordText(content.targetText, metrics: metrics, maxWidth: maxTextWidth)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(content.targetText.text)
                .accessibilityHint(interfaceLocaleID.text("Replay current word"))
                .accessibilityAddTraits(.isButton)

                builtWord(content.targetText, metrics: metrics, maxWidth: maxTextWidth)
                    .padding(.top, -3 * metrics.unit)
            }
            .frame(width: metrics.size.width, height: height, alignment: .top)
            .position(x: metrics.size.width / 2, y: top + height / 2)
        }
    }

    private func targetWordText(
        _ target: LearningTextRepresentation,
        metrics: SoccerBoardMetrics,
        maxWidth: CGFloat
    ) -> some View {
        Text(verbatim: target.text)
            .font(Self.boardFont(size: metrics.wordFontSize))
            .foregroundStyle(Color.black)
            .soccerFakeBold(Color.black, spread: metrics.wordFontSize / 64)
            .lineLimit(1)
            .minimumScaleFactor(0.35)
            .frame(maxWidth: maxWidth)
            .environment(\.layoutDirection, target.direction == .rightToLeft ? .rightToLeft : .leftToRight)
    }

    /// builtHebrewText: the letters kicked in so far, white Fredoka without bold.
    private func builtWord(
        _ target: LearningTextRepresentation,
        metrics: SoccerBoardMetrics,
        maxWidth: CGFloat
    ) -> some View {
        Text(verbatim: session.builtDisplayText ?? "")
            .font(Self.boardFont(size: metrics.builtFontSize))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.35)
            .frame(maxWidth: maxWidth, minHeight: metrics.builtFontSize * 1.2)
            .environment(\.layoutDirection, target.direction == .rightToLeft ? .rightToLeft : .leftToRight)
            .allowsHitTesting(false)
            .accessibilityLabel(interfaceFormat(
                "Built word, %@, %lld of %lld letters",
                constructedWordAccessibilityText,
                Int64(session.builtTokens.count),
                Int64(session.targetCount)
            ))
    }

    /// The letters keep their slots: a kicked letter leaves its gap, as Android
    /// hides the letter view instead of removing it. The view that owns the drag
    /// stays in place for the whole drag (it follows the finger), so the gesture
    /// is never torn down mid-drag. A kicked letter hides and cannot be grabbed
    /// while its ball flies; the other letters can be dragged at once, as on
    /// Android. A wrong letter is back in its slot as soon as its result counts.
    @ViewBuilder
    private func letterRow(metrics: SoccerBoardMetrics, keeperMinX: Double) -> some View {
        let balls = session.round.answerBalls
        let availableIDs = Set(session.availableBalls.map(\.id))
        let kickedIDs = kickedBallIDs
        let heldBallID = draggingBallID
        ForEach(Array(balls.enumerated()), id: \.element.id) { index, ball in
            let resting = slotCenter(index: index, count: balls.count, metrics: metrics)
            if availableIDs.contains(ball.id) {
                let isKicked = kickedIDs.contains(ball.id)
                let followsFinger = heldBallID == ball.id
                letterBall(ball, metrics: metrics)
                    .opacity(isKicked ? 0 : 1)
                    .position(followsFinger ? (dragPoint ?? resting) : resting)
                    .gesture(dragGesture(for: ball, resting: resting, metrics: metrics, keeperMinX: keeperMinX))
                    .allowsHitTesting(!isKicked)
                    .accessibilityAction {
                        beginAccessibleShot(ball: ball, resting: resting, metrics: metrics, keeperMinX: keeperMinX)
                    }
                    .accessibilityHidden(isKicked)
            }
        }
    }

    /// The letter the finger holds, if any.
    private var draggingBallID: SoccerBallID? {
        guard case .dragging(let ballID) = dragLifecycle.phase else { return nil }
        return ballID
    }

    /// The kicked letters whose result has not counted yet: flying, or landed and
    /// waiting for an earlier kick. None of them can be grabbed again.
    private var kickedBallIDs: Set<SoccerBallID> {
        Set(flights.map(\.ball.id))
    }

    /// Android's letters flow right to left in centred rows of 68 dp slots
    /// (56 dp circles with 6 dp margins) and wrap when a row is full.
    private func slotCenter(index: Int, count: Int, metrics: SoccerBoardMetrics) -> CGPoint {
        let capacity = max(1, metrics.rowCapacity)
        let row = index / capacity
        let column = index % capacity
        let itemsInRow = max(1, min(capacity, count - row * capacity))
        let rowWidth = CGFloat(itemsInRow) * metrics.letterPitch
        let rightEdge = metrics.size.width / 2 + rowWidth / 2
        return CGPoint(
            x: rightEdge - (CGFloat(column) + 0.5) * metrics.letterPitch,
            y: metrics.firstRowCenterY + CGFloat(row) * metrics.letterPitch
        )
    }

    /// CircleLetterView: a flat circle in the shuffled letter's palette colour
    /// with a bold 24 sp letter, white or navy (letterInk). The touch target never drops below
    /// Android's 56 dp letter view, even where the circle is drawn smaller.
    private func letterBall(_ ball: SoccerAnswerBall, metrics: SoccerBoardMetrics) -> some View {
        ZStack {
            Circle().fill(letterColor(for: ball))
            letterGlyph(ball, size: 24 * metrics.unit)
        }
        .frame(width: metrics.letterDiameter, height: metrics.letterDiameter)
        .frame(minWidth: 56, minHeight: 56)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ballAccessibilityLabel(for: ball))
        .accessibilityHint(interfaceLocaleID.text("Drag and drop the letters in the right order toward the goal"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func letterGlyph(_ ball: SoccerAnswerBall, size: CGFloat) -> some View {
        if let token = ball.orderedToken, let text = ball.orderedTokenDisplayText {
            Text(verbatim: text)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(letterInk(for: ball))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .environment(\.layoutDirection, token.direction == .rightToLeft ? .rightToLeft : .leftToRight)
        }
    }

    private func letterColor(for ball: SoccerAnswerBall) -> Color {
        let index = session.round.answerBalls.firstIndex(where: { $0.id == ball.id }) ?? 0
        return Self.letterPalette[index % Self.letterPalette.count]
    }

    /// White on the deep circles; the design's navy on the light ones, where a
    /// white letter was hard to read.
    private func letterInk(for ball: SoccerAnswerBall) -> Color {
        let index = session.round.answerBalls.firstIndex(where: { $0.id == ball.id }) ?? 0
        let light = Self.letterPaletteIsLight[index % Self.letterPaletteIsLight.count]
        return light ? MinikPretty.navy : Color.white
    }

    /// The kicked ball: minik_soccer_ball_new (36 dp) with the letter in black
    /// bold 18 sp on a tight white box, squashed to 70 % height.
    private func launchedBall(_ ball: SoccerAnswerBall, metrics: SoccerBoardMetrics) -> some View {
        let unit = metrics.unit
        return ZStack {
            MinikArtworkImage(name: MinikVisualAsset.soccerBall)
            if let token = ball.orderedToken, let text = ball.orderedTokenDisplayText {
                Text(verbatim: text)
                    .font(.system(size: 18 * unit, weight: .bold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .padding(.horizontal, unit)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 1.5 * unit))
                    .shadow(color: Color.black.opacity(0.5), radius: 1.5, y: 1)
                    .scaleEffect(x: 1, y: 0.7)
                    .offset(y: 1.5 * unit)
                    .environment(\.layoutDirection, token.direction == .rightToLeft ? .rightToLeft : .leftToRight)
            }
        }
        .frame(width: metrics.shotDiameter, height: metrics.shotDiameter)
    }

    /// playSoccerStarsTwinkle: for 2.5 s after a goal with the right letter the
    /// goal's stars blink twice a second and swell a little.
    @ViewBuilder
    private func goalStarsLayer(metrics: SoccerBoardMetrics, date: Date) -> some View {
        if let goalStarsStartedAt {
            let elapsed = date.timeIntervalSince(goalStarsStartedAt)
            if elapsed >= 0, elapsed < 2.5 {
                ForEach(0 ..< Self.goalStarLayout.count, id: \.self) { index in
                    goalStar(Self.goalStarLayout[index], metrics: metrics, elapsed: elapsed)
                }
            }
        }
    }

    private func goalStar(_ star: LanguageSoccerGoalStar, metrics: SoccerBoardMetrics, elapsed: Double) -> some View {
        let side = 24 * metrics.unit
        let age = max(0, elapsed - star.delay)
        let alphaPhase = age.truncatingRemainder(dividingBy: 0.45) / 0.45
        let scalePhase = age.truncatingRemainder(dividingBy: 0.6) / 0.6
        let starOpacity: Double = reduceMotion ? 1 : (elapsed < star.delay ? 0 : sin(Double.pi * alphaPhase))
        let starScale: Double = reduceMotion ? 1 : 1 + 0.18 * sin(Double.pi * scalePhase)
        let left = star.alignsRight
            ? CGFloat(metrics.goal.maxX) - side
            : CGFloat(metrics.goal.minX) + star.x * metrics.unit
        let top = CGFloat(metrics.goal.minY) + star.y * metrics.unit
        return MinikArtworkImage(name: "language_star_" + String(star.asset))
            .frame(width: side, height: side)
            .scaleEffect(CGFloat(starScale))
            .opacity(starOpacity)
            .position(x: left + side / 2, y: top + side / 2)
            .allowsHitTesting(false)
    }

    private func keeperView(metrics: SoccerBoardMetrics, minX: Double, date: Date) -> some View {
        let pose = keeperPose(metrics: metrics, minX: minX, date: date)
        return MinikArtworkImage(name: MinikVisualAsset.soccerGoalie)
            .frame(width: metrics.keeperSize.width, height: metrics.keeperSize.height)
            .scaleEffect(x: pose.mirrored ? -pose.scaleX : pose.scaleX, y: pose.scaleY, anchor: .bottom)
            .offset(y: pose.lift)
            .position(
                x: CGFloat(minX) + metrics.keeperSize.width / 2,
                y: metrics.keeperBottomY - metrics.keeperSize.height / 2
            )
            .allowsHitTesting(false)
    }

    /// Android swaps minik_plus_goalie for its mirror image (_right) while the
    /// keeper moves right, and faces the goal's middle once it stops.
    private func keeperPose(metrics: SoccerBoardMetrics, minX: Double, date: Date) -> LanguageSoccerKeeperPose {
        if let celebration = roundCelebration, celebration.keeperWon, !reduceMotion {
            return hoppingKeeperPose(
                elapsed: max(0, date.timeIntervalSince(celebration.startedAt)),
                height: Double(metrics.keeperSize.height)
            )
        }
        let earlier = keeperPosition(at: date.addingTimeInterval(-0.05), layout: metrics)
        let facesRight: Bool
        if minX > earlier + 0.01 {
            facesRight = true
        } else if minX < earlier - 0.01 {
            facesRight = false
        } else {
            let keeperCenter = minX + Double(metrics.keeperSize.width) / 2
            facesRight = keeperCenter < metrics.goal.minX + metrics.goal.width / 2 - 1
        }
        return LanguageSoccerKeeperPose(mirrored: facesRight, scaleX: 1, scaleY: 1, lift: 0)
    }

    /// LettersSoccerGame.animateSoccerBoy after a lost match: a small squash, a
    /// jump of a quarter of the keeper's height and a landing, turning around
    /// after every hop.
    private func hoppingKeeperPose(elapsed: Double, height: Double) -> LanguageSoccerKeeperPose {
        let period = 0.7
        let hop = Int(elapsed / period)
        let time = elapsed - Double(hop) * period
        var scaleX = 1.0
        var scaleY = 1.0
        var lift = 0.0
        if time < 0.14 {
            let progress = time / 0.14
            scaleX = 1 + 0.05 * progress
            scaleY = 1 - 0.1 * progress
        } else if time < 0.42 {
            let progress = (1 - cos(Double.pi * (time - 0.14) / 0.28)) / 2
            scaleX = 1.05
            scaleY = 0.9
            lift = -0.25 * height * progress
        } else {
            let progress = (1 - cos(Double.pi * (time - 0.42) / 0.28)) / 2
            scaleX = 1.05 - 0.05 * progress
            scaleY = 0.9 + 0.1 * progress
            lift = -0.25 * height * (1 - progress)
        }
        return LanguageSoccerKeeperPose(
            mirrored: hop % 2 == 1,
            scaleX: CGFloat(scaleX),
            scaleY: CGFloat(scaleY),
            lift: CGFloat(lift)
        )
    }

    /// Stands in for Android's minik_plus_soccer win video, which is not bundled
    /// on iOS: from two seconds in, Minik fades in over the pitch and celebrates.
    private func winningMinik(
        _ celebration: LanguageSoccerRoundCelebration,
        metrics: SoccerBoardMetrics,
        date: Date
    ) -> some View {
        let elapsed = date.timeIntervalSince(celebration.startedAt) - 2
        let fadeIn = min(1, max(0, elapsed / 0.6))
        let fadeOut = min(1, max(0, (Self.winCelebrationSeconds - 2 - elapsed) / 0.6))
        let hop: Double = reduceMotion ? 0 : abs(sin(Double.pi * max(0, elapsed) / 0.45))
        let height = metrics.fieldFrame.height * 0.5
        return MinikArtworkImage(name: MinikVisualAsset.success)
            .frame(width: height * 0.75, height: height)
            .offset(y: CGFloat(-hop) * 18 * metrics.unit)
            .opacity(min(fadeIn, fadeOut))
            .position(x: metrics.fieldFrame.midX, y: metrics.fieldFrame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func dragGesture(
        for ball: SoccerAnswerBall,
        resting: CGPoint,
        metrics: SoccerBoardMetrics,
        keeperMinX: Double
    ) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("languageSoccerGame"))
            .onChanged { value in
                guard value.startLocation.y > metrics.releaseLineY else { return }
                // Android has no input lock: a free finger grabs any letter not in
                // the air, even while other balls still fly. The finger that kicked
                // this letter never grabs it again before it is lifted.
                if dragLifecycle.acceptsNewDrag {
                    guard kickingDragStarts[ball.id] != value.startLocation, grabLetter(ball.id) else { return }
                    lastDragSample = .init(point: value.startLocation, date: Date())
                    // Android keeps the letter where it was grabbed under the finger.
                    dragOffset = CGSize(
                        width: resting.x - value.startLocation.x,
                        height: resting.y - value.startLocation.y
                    )
                }
                guard draggingBallID == ball.id else { return }
                updateVelocity(with: value.location)
                let letterPoint = draggedLetterPoint(for: value.location)
                dragPoint = letterPoint
                if LanguageSoccerLaunchPolicy.shouldLaunchDuringDrag(
                    locationY: Double(value.location.y),
                    releaseLineY: Double(metrics.releaseLineY)
                ) {
                    kickingDragStarts[ball.id] = value.startLocation
                    launch(ball: ball, start: letterPoint, metrics: metrics, keeperMinX: keeperMinX)
                }
            }
            .onEnded { value in
                if kickingDragStarts[ball.id] == value.startLocation {
                    kickingDragStarts[ball.id] = nil
                }
                guard draggingBallID == ball.id else { return }
                updateVelocity(with: value.location)
                if LanguageSoccerLaunchPolicy.shouldLaunchOnRelease(
                    locationY: Double(value.location.y),
                    releaseLineY: Double(metrics.releaseLineY)
                ) {
                    launch(
                        ball: ball,
                        start: draggedLetterPoint(for: value.location),
                        metrics: metrics,
                        keeperMinX: keeperMinX
                    )
                } else {
                    dragLifecycle.cancelDrag(ballID: ball.id)
                    dragPoint = nil
                    lastDragSample = nil
                    dragOffset = .zero
                }
            }
    }

    /// The finger takes a letter, unless that letter is already kicked and its
    /// result has not counted yet.
    private func grabLetter(_ ballID: SoccerBallID) -> Bool {
        guard !kickedBallIDs.contains(ballID) else { return false }
        return dragLifecycle.beginDragging(ballID: ballID)
    }

    private func draggedLetterPoint(for location: CGPoint) -> CGPoint {
        CGPoint(x: location.x + dragOffset.width, y: location.y + dragOffset.height)
    }

    private func updateVelocity(with point: CGPoint) {
        let now = Date()
        if let lastDragSample {
            let seconds = max(0.001, now.timeIntervalSince(lastDragSample.date))
            dragVelocity = LanguageSoccerVector(
                dx: Double(point.x - lastDragSample.point.x) / seconds,
                dy: Double(point.y - lastDragSample.point.y) / seconds
            )
        }
        lastDragSample = .init(point: point, date: now)
    }

    private func beginAccessibleShot(
        ball: SoccerAnswerBall,
        resting: CGPoint,
        metrics: SoccerBoardMetrics,
        keeperMinX: Double
    ) {
        guard grabLetter(ball.id) else { return }
        dragVelocity = .init(dx: 0, dy: -1)
        launch(ball: ball, start: resting, metrics: metrics, keeperMinX: keeperMinX)
    }

    /// Kicks the dragged letter. The kicks still in the air count first, as the
    /// word is built in kick order, so the letter is judged against them. Its ball
    /// then flies on its own and the finger is free for the next letter at once:
    /// Android's LettersSoccerGame has no wait between kicks.
    private func launch(
        ball: SoccerAnswerBall,
        start: CGPoint,
        metrics: SoccerBoardMetrics,
        keeperMinX: Double
    ) {
        let kickSession = practice.sessionForKick(ball.id, after: flights.map(\.ball.id))
        guard let shotID = dragLifecycle.launch(ballID: ball.id) else { return }
        let launchedLifecycle = dragLifecycle
        dragLifecycle = LanguageSoccerShotLifecycle()
        dragPoint = nil
        dragOffset = .zero
        lastDragSample = nil
        guard kickSession.selectedBallID == ball.id else { return }

        hasKicked = true
        lastSettledOutcome = nil
        recordAttempt(in: kickSession)
        // The next letter's answer time runs from this kick.
        targetStartedAt = Date()
        if let cue = kickSession.selectedOrderedTokenSpeechCue { speechPlayer.speak(cue) }
        soundPlayer.playKick()

        let preliminary = shotGeometry(layout: metrics, keeperMinX: keeperMinX).resolve(
            start: .init(x: Double(start.x), y: Double(start.y)),
            dragVelocity: dragVelocity
        )
        let projectedKeeperX = keeperPosition(
            at: Date().addingTimeInterval(preliminary.durationSeconds),
            layout: metrics
        )
        let resolution = shotGeometry(layout: metrics, keeperMinX: projectedKeeperX).resolve(
            start: .init(x: Double(start.x), y: Double(start.y)),
            dragVelocity: dragVelocity
        )
        flights.append(LanguageSoccerFlight(
            id: shotID,
            ball: ball,
            resolution: resolution,
            keeperXAtImpact: projectedKeeperX,
            lifecycle: launchedLifecycle,
            point: start,
            shotTask: nil
        ))
        runShot(shotID: shotID, start: start, resolution: resolution, metrics: metrics)
    }

    private func shotGeometry(layout: SoccerBoardMetrics, keeperMinX: Double) -> LanguageSoccerShotGeometry {
        LanguageSoccerShotGeometry(
            field: layout.field,
            goal: layout.goal,
            keeper: LanguageSoccerRect(
                minX: keeperMinX,
                minY: Double(layout.keeperBottomY - layout.keeperSize.height),
                width: Double(layout.keeperSize.width),
                height: Double(layout.keeperSize.height)
            ),
            ballRadius: Double(layout.shotDiameter) / 2,
            postThickness: max(6 * Double(layout.unit), layout.goal.width * 0.01)
        )
    }

    /// One kicked ball's flight, on its own task so that other balls can fly at
    /// the same time: to the goal line, then on into the net or back off the
    /// keeper or a post. When it lands, the results that are due count.
    private func runShot(
        shotID: UUID,
        start: CGPoint,
        resolution: LanguageSoccerShotResolution,
        metrics: SoccerBoardMetrics
    ) {
        let shotTask = Task { @MainActor in
            guard startFlight(shotID) else { return }
            let flightDuration = reduceMotion ? 0.02 : resolution.durationSeconds
            let impact = CGPoint(x: resolution.impactPoint.x, y: resolution.impactPoint.y)
            withAnimation(reduceMotion ? nil : .linear(duration: flightDuration)) {
                moveFlight(shotID, to: impact)
            }
            try? await Task.sleep(for: .seconds(flightDuration))
            guard !Task.isCancelled else { return }

            if let rebound = resolution.reboundPoint {
                guard startRebound(shotID) else { return }
                let reboundDuration = reduceMotion ? 0.02 : (resolution.collision == .keeper ? 0.5 : 0.45)
                withAnimation(reduceMotion ? nil : .easeOut(duration: reboundDuration)) {
                    moveFlight(shotID, to: CGPoint(x: rebound.x, y: rebound.y))
                }
                soundPlayer.playKick()
                try? await Task.sleep(for: .seconds(reboundDuration))
                guard !Task.isCancelled else { return }
            } else if resolution.outcome == .goal, !reduceMotion {
                // Android flies a goal on at the same speed, 40 dp past the goal
                // line into the net, before the ball disappears.
                let net = netPoint(from: start, entry: impact, metrics: metrics)
                let netDuration = netFlightDuration(
                    from: start,
                    entry: impact,
                    net: net,
                    flightDuration: flightDuration
                )
                withAnimation(.linear(duration: netDuration)) {
                    moveFlight(shotID, to: net)
                }
                try? await Task.sleep(for: .seconds(netDuration))
                guard !Task.isCancelled else { return }
            }

            // Android's finishShot hides the ball as soon as the shot ends.
            guard landFlight(shotID, outcome: resolution.outcome) else { return }
            settleLandedShots(metrics: metrics)
        }
        if let index = flightIndex(shotID) {
            flights[index].shotTask = shotTask
        }
    }

    private func flightIndex(_ shotID: UUID) -> Int? {
        flights.firstIndex { $0.id == shotID }
    }

    private func startFlight(_ shotID: UUID) -> Bool {
        guard let index = flightIndex(shotID) else { return false }
        return flights[index].lifecycle.beginFlight(shotID: shotID)
    }

    private func startRebound(_ shotID: UUID) -> Bool {
        guard let index = flightIndex(shotID) else { return false }
        return flights[index].lifecycle.beginRebound(shotID: shotID)
    }

    private func moveFlight(_ shotID: UUID, to point: CGPoint) {
        guard let index = flightIndex(shotID) else { return }
        flights[index].point = point
    }

    /// The ball's flight is over: it disappears, and its result waits for the
    /// kicks before it.
    private func landFlight(_ shotID: UUID, outcome: GameOutcome) -> Bool {
        guard let index = flightIndex(shotID),
              flights[index].lifecycle.finalize(shotID: shotID, outcome: outcome) else {
            return false
        }
        flights[index].point = nil
        flights[index].shotTask = nil
        return true
    }

    /// Results count in kick order, as the word is built: the oldest kick counts
    /// once its ball has landed, and a ball that landed sooner waits for it (an
    /// earlier, slanting shot can fly longer). Each kick was judged against the
    /// kicks before it, so the order keeps every judgment. The keeper's
    /// bookkeeping follows once no ball is on its way.
    private func settleLandedShots(metrics: SoccerBoardMetrics?) {
        while roundCelebration == nil,
              let flight = flights.first,
              flight.lifecycle.landedOutcome != nil {
            flights.removeFirst()
            settle(flight)
        }
        updateKeeperIfAirIsClear(metrics: metrics)
    }

    /// One kick's result: the physical outcome worked out at the kick scores the
    /// letter, which is judged as it was when kicked (the same kicks count before
    /// it). A right letter joins the word, a wrong one is back in its slot at once,
    /// as Android shows it again in finishShot.
    private func settle(_ flight: LanguageSoccerFlight) {
        let resolution = flight.resolution
        practice.selectBall(flight.ball.id)
        guard session.selectedBallID == flight.ball.id else { return }
        let educationalWasCorrect = session.educationalIsCorrect
        practice.resolveShot(outcome: resolution.outcome)
        lastSettledOutcome = resolution.outcome
        let correctGoal = educationalWasCorrect == true && resolution.outcome == .goal
        if educationalWasCorrect == false, resolution.outcome == .goal {
            soundPlayer.playWrongLetterGoal()
        }
        if correctGoal {
            goalStarsStartedAt = Date()
        }
        let completedRound = session.isComplete
        keeperTallies.append(LanguageSoccerKeeperTally(
            scored: resolution.outcome == .goal,
            gameContinues: !completedRound,
            keeperXAtImpact: flight.keeperXAtImpact
        ))
        if completedRound {
            celebrateCompletedRound()
        } else {
            if correctGoal, goalSpeechAllowed() {
                speechPlayer.enqueueInterfaceSpeech(
                    interfaceLocaleID.text("Goal"),
                    interfaceLocale: interfaceLocaleID
                )
            }
            practice.prepareNextKick()
        }
    }

    /// The keeper changes only while no ball is on its way, so every ball still in
    /// the air meets the keeper its outcome was worked out against at its kick. A
    /// moving keeper that stops stays where it is now.
    private func updateKeeperIfAirIsClear(metrics: SoccerBoardMetrics?) {
        guard !keeperTallies.isEmpty,
              !flights.contains(where: { $0.lifecycle.isAirborne }) else { return }
        let currentX = metrics.map { keeperPosition(at: Date(), layout: $0) }
        let tallies = keeperTallies
        keeperTallies.removeAll()
        for tally in tallies {
            totalShots += 1
            if tally.scored { goals += 1 }
            recentGoalResults.append(tally.scored)
            if recentGoalResults.count > 10 { recentGoalResults.removeFirst() }
            updateKeeperAfterShot(
                currentX: currentX ?? tally.keeperXAtImpact,
                gameContinues: tally.gameContinues
            )
        }
    }

    /// The word is complete: the final score, the result and Android's
    /// celebration, then the next word after 6.5 s (a win) or 4 s.
    private func celebrateCompletedRound() {
        let celebration = LanguageSoccerRoundCelebration(
            startedAt: Date(),
            childScore: session.childScore,
            keeperScore: session.keeperScore
        )
        roundCelebration = celebration
        onMatchResolved(completedMatchOutcome)
        speakCompletedRoundResult()
        // Android keeps a won match on screen for 6.5 s in Plus, others for 4 s.
        let feedbackDuration = celebration.childWon ? Self.winCelebrationSeconds : Self.otherCelebrationSeconds
        // No speech over Minik's victory celebration: Android stops all speech
        // when its victory video starts, two seconds after the end.
        let speechCutoff: Double? = celebration.childWon ? Self.winningMinikDelay : nil
        celebrationTask?.cancel()
        celebrationTask = Task { @MainActor in
            if let speechCutoff {
                try? await Task.sleep(for: .seconds(speechCutoff))
                guard !Task.isCancelled else { return }
                stopSpeech()
            }
            try? await Task.sleep(for: .seconds(feedbackDuration - (speechCutoff ?? 0)))
            guard !Task.isCancelled else { return }
            finishCompletedRound(speakNextRound: true)
        }
    }

    private func cancelFlightTasks() {
        for flight in flights {
            flight.shotTask?.cancel()
        }
    }

    /// Where a goal stops in the net: on along its line to 40 dp past the goal
    /// line, as Android's overshoot, or sooner where the side netting stops a
    /// slanting ball, so a goal always ends inside the goal.
    private func netPoint(from start: CGPoint, entry: CGPoint, metrics: SoccerBoardMetrics) -> CGPoint {
        let depth = 40 * metrics.unit
        let deltaX = entry.x - start.x
        let deltaY = entry.y - start.y
        guard deltaY < -0.001 else {
            return CGPoint(x: entry.x, y: entry.y - depth)
        }
        var scale = depth / -deltaY
        let postThickness = max(6 * metrics.unit, CGFloat(metrics.goal.width) * 0.01)
        let sideInset = postThickness + metrics.shotDiameter / 2
        let minX = CGFloat(metrics.goal.minX) + sideInset
        let maxX = CGFloat(metrics.goal.maxX) - sideInset
        let projectedX = entry.x + deltaX * scale
        if projectedX < minX, deltaX < 0 {
            scale = max(0, (minX - entry.x) / deltaX)
        } else if projectedX > maxX, deltaX > 0 {
            scale = max(0, (maxX - entry.x) / deltaX)
        }
        return CGPoint(x: entry.x + deltaX * scale, y: entry.y + deltaY * scale)
    }

    /// The net segment keeps the flight's own speed, as Android's single linear
    /// animation does.
    private func netFlightDuration(
        from start: CGPoint,
        entry: CGPoint,
        net: CGPoint,
        flightDuration: Double
    ) -> Double {
        let flightX = Double(entry.x - start.x)
        let flightY = Double(entry.y - start.y)
        let netX = Double(net.x - entry.x)
        let netY = Double(net.y - entry.y)
        let flightLength = (flightX * flightX + flightY * flightY).squareRoot()
        let netLength = (netX * netX + netY * netY).squareRoot()
        let speed: Double
        if flightLength > 1, flightDuration > 0 {
            speed = flightLength / flightDuration
        } else {
            speed = 420
        }
        return min(0.5, max(0.02, netLength / speed))
    }

    private func updateKeeperAfterShot(currentX: Double, gameContinues: Bool) {
        guard gameContinues else { return }
        if tuning.level == .a, keeperMoving {
            let settles = tuning.settlesToCenterAfterMovingShot(
                recentGoals: recentGoalResults.filter { $0 }.count,
                windowSize: recentGoalResults.count,
                randomBucket: Int.random(in: 0 ..< 20)
            )
            stationaryKeeperX = settles ? nil : currentX
        }
        attemptIndex += 1
        keeperMoving = tuning.shouldMove(atAttemptIndex: attemptIndex)
        if keeperMoving { stationaryKeeperX = nil }
    }

    /// The celebration is over (or the app left the foreground during it): the
    /// next word starts. Runs once per completed word.
    private func finishCompletedRound(speakNextRound: Bool) {
        guard roundCelebration != nil, session.isComplete else { return }
        celebrationTask = nil
        roundCelebration = nil
        goalStarsStartedAt = nil
        lastSettledOutcome = nil
        cancelFlightTasks()
        flights.removeAll()
        kickingDragStarts.removeAll()
        onWordCompleted()
        guard practice.advanceToNextRound() else { return }
        if let boundary = practice.lastAdvanceBoundary {
            onPoolExhausted(boundary)
            if let replacement = makeNextPracticeSession?() {
                practice = replacement
            }
        }
        roundStartedAt = Date()
        keeperMoving = tuning.initiallyMoves
        stationaryKeeperX = nil
        targetStartedAt = Date()
        if speakNextRound { speakRoundCue() }
    }

    private var completedMatchOutcome: LanguageSoccerMatchOutcome {
        if session.childScore > session.keeperScore {
            return .childWin
        }
        if session.childScore == session.keeperScore {
            return .draw
        }
        return .minikWin
    }

    /// The kick's attempt, judged as `kickSession` sees it: after the kicks still
    /// waiting for their result, so the letter index and the verdict match the
    /// result that counts later.
    private func recordAttempt(in kickSession: SoccerSession) {
        guard let correct = kickSession.educationalIsCorrect,
              let attempt = attemptTracker.makeAttempt(
                  presentationIndex: practice.roundNumber,
                  contentItemID: practice.currentContentItemID,
                  tokenIndex: kickSession.progressCount,
                  result: correct ? .correct : .incorrect,
                  responseDurationSeconds: Date().timeIntervalSince(targetStartedAt),
                  activityFamily: .soccer,
                  languageVocabularyLevel: kickSession.orderedTokenContent?.vocabularyLevel
              ) else { return }
        onAttempt(attempt)
    }

    private func keeperPosition(at date: Date, layout: SoccerBoardMetrics) -> Double {
        if !keeperMoving, let stationaryKeeperX {
            return min(
                layout.goal.maxX - Double(layout.keeperSize.width),
                max(layout.goal.minX, stationaryKeeperX)
            )
        }
        return tuning.keeperMinX(
            at: date.timeIntervalSince(roundStartedAt),
            isMoving: keeperMoving,
            totalShots: totalShots,
            goals: goals,
            goal: layout.goal,
            keeperWidth: Double(layout.keeperSize.width)
        )
    }

    // MARK: - Introduction (SoccerIntroDialog)

    private var introductionOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            GeometryReader { proxy in
                let wide = proxy.size.width >= 600
                let cardWidth = max(1, proxy.size.width * (wide ? 0.9 : 0.93))
                let cardHeight = max(1, proxy.size.height * 0.86)
                introductionCard(
                    metrics: LanguageSoccerIntroMetrics(wide: wide),
                    width: cardWidth,
                    height: cardHeight
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The dialog fills 92 % of the width and most of the height. Its content
    /// sits on the card as on Android while it fits; with larger text it scrolls
    /// instead of losing the last lines and the Start button.
    private func introductionCard(
        metrics: LanguageSoccerIntroMetrics,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ViewThatFits(in: .vertical) {
            introductionCardContent(metrics: metrics)
            ScrollView {
                introductionCardContent(metrics: metrics)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: width, height: height)
        .background { introductionBackdrop(metrics: metrics) }
        .overlay { introductionStar(metrics: metrics) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // The design's white rim in place of the card's dark outline.
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .shadow(color: MinikPretty.navy.opacity(0.25), radius: 10, y: 5)
    }

    private func introductionCardContent(metrics: LanguageSoccerIntroMetrics) -> some View {
        VStack(spacing: 0) {
            // The design's navy Fredoka title.
            Text(interfaceLocaleID.text("Soccer"))
                .font(MinikPretty.titleFont(min(introTitleFontBase, 56) * metrics.titleScale))
                .foregroundStyle(MinikPretty.navy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, metrics.titleSidePadding)
                .padding(.top, metrics.titleTop)
                .accessibilityAddTraits(.isHeader)
            // explainText: four short lines (QA ISSUE-008) in bold navy from the
            // reading start, not centred, read by VoiceOver as one block.
            VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                ForEach(soccerIntroductionLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: introTextFontBase * metrics.textScale, weight: .bold))
                        .foregroundStyle(MinikPretty.navy)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .padding(.horizontal, metrics.textSideMargin)
            .padding(.top, metrics.textTop)
            moreInformation(metrics: metrics)
                .padding(.horizontal, metrics.textSideMargin)
                .padding(.top, metrics.moreInformationTop)
            Spacer(minLength: 12)
            introductionBottomRow(metrics: metrics)
        }
        .frame(maxWidth: .infinity)
    }

    /// "More Information" (QA ISSUE-008): the rest of the rules, folded away under
    /// a lavender pill with a chevron that opens a lavender panel below it. It is
    /// closed whenever the introduction appears; the four lines never need it.
    private func moreInformation(metrics: LanguageSoccerIntroMetrics) -> some View {
        let size = introTextFontBase * metrics.textScale
        return VStack(alignment: .leading, spacing: metrics.lineSpacing) {
            Button(action: toggleMoreInformation) {
                HStack(spacing: 8) {
                    Text(interfaceLocaleID.text("More Information"))
                        .font(MinikPretty.titleFont(size * 0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: size * 0.65, weight: .bold))
                        .rotationEffect(.degrees(showsMoreInformation ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(MinikPretty.navy)
                .padding(.horizontal, size * 0.9)
                .frame(minHeight: max(44, size * 1.9))
                .background(MinikPretty.lavender, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(MinikPretty.lavenderRim, lineWidth: 1.5)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityValue(moreInformationState)

            if showsMoreInformation {
                VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                    ForEach(soccerMoreInformationLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: size * 0.85, weight: .semibold))
                            .foregroundStyle(MinikPretty.navy)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(metrics.moreInformationPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    MinikPretty.lavender,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(MinikPretty.lavenderRim, lineWidth: 1.5)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opening "More Information" restarts the Start countdown, so the match does
    /// not begin by itself while the extra rules are being read.
    private func toggleMoreInformation() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            showsMoreInformation.toggle()
        }
        if showsMoreInformation, showsIntroduction {
            startIntroductionCountdown()
        }
    }

    /// VoiceOver hears whether "More Information" is open.
    private var moreInformationState: String {
        if showsMoreInformation {
            return interfaceLocaleID.text("Expanded")
        }
        return interfaceLocaleID.text("Collapsed")
    }

    /// Minik in goalkeeper gloves at the bottom left, the faded yellow ball at the
    /// bottom right (both physical sides, as Android anchors them) and the design's
    /// sunny Start pill with its countdown centred between them.
    private func introductionBottomRow(metrics: LanguageSoccerIntroMetrics) -> some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 0) {
                MinikArtworkImage(name: MinikVisualAsset.soccerGoalie)
                    .frame(width: metrics.goalieSize.width, height: metrics.goalieSize.height)
                    .padding(.leading, metrics.goalieLeading)
                    .padding(.bottom, metrics.bottomInset)
                Spacer(minLength: 0)
                // minik_soccer_ball is yellow and black; the bundled ball is tinted.
                MinikArtworkImage(name: MinikVisualAsset.soccerBall)
                    .colorMultiply(Self.introBallYellow)
                    .frame(width: metrics.ballSide, height: metrics.ballSide)
                    .opacity(metrics.ballOpacity)
                    .padding(.trailing, metrics.ballTrailing)
                    .padding(.bottom, metrics.ballBottom)
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)

            Button(action: dismissIntroduction) {
                Text(introductionStartLabel)
                    .font(MinikPretty.titleFont(min(introButtonFontBase, 34) * metrics.buttonScale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .buttonStyle(MinikPrettyButtonStyle(.yellow))
            .accessibilityLabel(interfaceLocaleID.text("Start"))
            .padding(.bottom, metrics.buttonBottom)
        }
        .frame(maxWidth: .infinity)
    }

    /// The card in the rainbow-sky design: the sky inside the card's rounded corners
    /// and a frosted panel 14 points in from its edges (bg_pretty_inset_panel: white
    /// at 91% with a white rim and 24 dp corners), in place of plus_background and
    /// the yellow splash.
    private func introductionBackdrop(metrics: LanguageSoccerIntroMetrics) -> some View {
        ZStack {
            MinikSkyBackground()
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.91))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                }
                .padding(.horizontal, metrics.frameInsetX)
                .padding(.vertical, metrics.frameInsetY)
        }
        .accessibilityHidden(true)
    }

    /// mimik_star, the star hanging on a beaded string at the card's top right.
    /// That artwork is not bundled on iOS; the yellow goal star hangs on a drawn
    /// string in its place.
    private func introductionStar(metrics: LanguageSoccerIntroMetrics) -> some View {
        let box = metrics.starBox
        let starSide = box.height * 0.5
        return ZStack(alignment: .top) {
            LanguageSoccerStarString()
                .stroke(
                    Self.introStarYellow,
                    style: StrokeStyle(
                        lineWidth: max(2, box.height * 0.04),
                        lineCap: .round,
                        dash: [0.1, box.height * 0.07]
                    )
                )
                .frame(width: box.width, height: box.height - starSide * 0.8)
            MinikArtworkImage(name: "language_star_1")
                .frame(width: starSide, height: starSide)
                .rotationEffect(.degrees(-12))
                .padding(.top, box.height - starSide)
        }
        .frame(width: box.width, height: box.height, alignment: .top)
        .padding(.trailing, metrics.frameInsetX)
        .padding(.top, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The four short lines children see, and hear, before the match (QA ISSUE-008).
    private var soccerIntroductionLines: [String] {
        [
            interfaceLocaleID.text("Drag the letters in the correct order to spell the word shown."),
            interfaceLocaleID.text("Try to score a goal against Minik with each letter."),
            interfaceLocaleID.text("Correct letter + goal = 1 point for you!"),
            interfaceLocaleID.text("Wrong letter + no goal = 1 point for Minik!")
        ]
    }

    /// What is read aloud: the four lines, then Android's existing closing line (the end of
    /// game_dialog_speak_text), as SoccerIntroDialog reads them (2df3a2a).
    private var soccerIntroductionText: String {
        (soccerIntroductionLines + [interfaceLocaleID.text("Tap Start to begin. Good luck!")])
            .joined(separator: "\n")
    }

    /// The rest of the game's rules, under "More Information": how a kick works,
    /// the two scoring cases the four lines leave out, the end of the match and
    /// replaying the word.
    private var soccerMoreInformationLines: [String] {
        [
            interfaceLocaleID.text("Drag letters upward in the correct order, past the dashed line, to kick them toward the goal."),
            interfaceLocaleID.text("Correct letter + no goal = no point, but the letter still goes into the word."),
            interfaceLocaleID.text("Wrong letter + goal = no point, and the letter comes back to try again."),
            interfaceLocaleID.text("When the word is complete, whoever has more points wins."),
            interfaceLocaleID.text("Tap the word or the picture to hear it again.")
        ]
    }

    /// start_with_seconds: "Start… 44" down to "Start… 1".
    private var introductionStartLabel: String {
        interfaceLocaleID.text("Start") + "… " + String(introductionSecondsLeft)
    }

    private func handleAppearance() {
        guard !didEvaluateIntroduction else {
            if showsIntroduction, introductionCountdown == nil { startIntroductionCountdown() }
            return
        }
        didEvaluateIntroduction = true
        if introductionRepository.registerPresentationIfNeeded() {
            showsIntroduction = true
            interfaceSpeechPlayer.speak(soccerIntroductionText, interfaceLocale: interfaceLocaleID)
            startIntroductionCountdown()
        } else {
            speakRoundCue()
        }
    }

    /// SoccerIntroDialog counts its Start button down from 45 seconds and then
    /// starts the match by itself.
    private func startIntroductionCountdown() {
        introductionCountdown?.cancel()
        introductionSecondsLeft = 44
        introductionCountdown = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if introductionSecondsLeft > 1 {
                    introductionSecondsLeft -= 1
                } else {
                    dismissIntroduction()
                    return
                }
            }
        }
    }

    private func dismissIntroduction() {
        guard showsIntroduction else { return }
        introductionCountdown?.cancel()
        introductionCountdown = nil
        interfaceSpeechPlayer.stop()
        showsIntroduction = false
        roundStartedAt = Date()
        speakRoundCue()
    }

    private func speakRoundCue() {
        speechPlayer.speak(practice.currentSpeechCue)
    }

    /// The match is over: whatever the last kicks left queued ("Goal") is cut first,
    /// then only the word and the result are said, as on Android.
    private func speakCompletedRoundResult() {
        stopSpeech()
        speechPlayer.speak(practice.currentSpeechCue)
        let result: String.LocalizationValue
        if session.childScore > session.keeperScore {
            result = "You won!"
        } else if session.childScore == session.keeperScore {
            result = "It’s a tie!"
        } else {
            result = "Minik won!"
        }
        speechPlayer.enqueueInterfaceSpeech(
            interfaceLocaleID.text(result),
            interfaceLocale: interfaceLocaleID
        )
    }

    /// Goals kicked one right after another say "Goal" at most once every 2.5 s
    /// (Android goalSpeechAllowed), so the cheers never pile up.
    private func goalSpeechAllowed() -> Bool {
        let now = Date()
        if let lastGoalSpeechAt, now.timeIntervalSince(lastGoalSpeechAt) < Self.goalSpeechInterval {
            return false
        }
        lastGoalSpeechAt = now
        return true
    }

    /// Stops the speech only; the game's sounds play on.
    private func stopSpeech() {
        speechPlayer.stop()
        interfaceSpeechPlayer.stop()
    }

    private func exitActivity() {
        stopAudioAndMotion()
        onExit()
    }

    private func stopAudioAndMotion() {
        cancelFlightTasks()
        flights.removeAll()
        celebrationTask?.cancel()
        celebrationTask = nil
        introductionCountdown?.cancel()
        introductionCountdown = nil
        practice.cancelUnresolvedShot()
        dragLifecycle.cancelAll()
        dragPoint = nil
        roundCelebration = nil
        stopAudio()
    }

    /// The app leaves the foreground: the balls that already landed still count,
    /// in kick order. A kick still in the air is dropped, and so is every kick
    /// after it, since each was judged after it; their letters are back in their
    /// slots. A finished word moves straight on to the next one.
    private func suspendActiveShot() {
        cancelFlightTasks()
        settleLandedShots(metrics: nil)
        flights.removeAll()
        updateKeeperIfAirIsClear(metrics: nil)
        practice.cancelUnresolvedShot()
        dragLifecycle.cancelAll()
        dragPoint = nil
        dragOffset = .zero
        lastDragSample = nil
        if roundCelebration != nil {
            celebrationTask?.cancel()
            finishCompletedRound(speakNextRound: false)
        }
        stopAudio()
    }

    private func stopAudio() {
        speechPlayer.stop()
        interfaceSpeechPlayer.stop()
        soundPlayer.stop()
    }

    private func ballAccessibilityLabel(for ball: SoccerAnswerBall) -> String {
        ball.orderedToken?.speechText ?? ball.orderedToken?.text ?? ball.representation.accessibilityDescription
    }

    private var constructedWordAccessibilityText: String {
        guard let text = session.builtDisplayText, !text.isEmpty else { return interfaceLocaleID.text("empty") }
        return text
    }

    private var sceneAccessibilityLabel: String {
        if let outcome = lastSettledOutcome {
            return interfaceFormat("Soccer field. %@.", outcomeLabel(outcome))
        }
        return interfaceLocaleID.text("Drag and drop the letters in the right order toward the goal")
    }

    private func outcomeLabel(_ outcome: GameOutcome) -> String {
        switch outcome {
        case .goal: interfaceLocaleID.text("Goal")
        case .miss: interfaceLocaleID.text("Miss")
        case .saved: interfaceLocaleID.text("Saved")
        }
    }

    private func interfaceFormat(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: interfaceLocaleID.text(key), arguments: arguments)
    }

    /// Android draws the word, the letters kicked so far and the scores in
    /// Fredoka Medium. The bundled face is Android's own file and covers the
    /// Hebrew letters too, so Hebrew words keep the rounded look.
    private static func boardFont(size: CGFloat) -> Font {
        Font.custom("Fredoka-Medium", fixedSize: size)
    }

    private static let winCelebrationSeconds = 6.5
    private static let otherCelebrationSeconds = 4.0
    /// winningMinik fades Minik in two seconds after a won match ends; the speech
    /// stops then.
    private static let winningMinikDelay = 2.0
    /// Android's goalSpeechAllowed: "Goal" at most once every 2.5 s.
    private static let goalSpeechInterval = 2.5
    /// The score colours: Android's #E91E63, and its #29BA74 a shade deeper (#189F5D)
    /// so the digits stay readable on the card's light wash.
    private static let scoreGreen = Color(red: 0.094, green: 0.624, blue: 0.365)
    private static let scorePink = Color(red: 0.914, green: 0.118, blue: 0.388)
    /// release_line_dash: #3F4FAD at half opacity.
    private static let releaseLineInk = Color(red: 0.247, green: 0.31, blue: 0.678).opacity(0.5)
    /// The introduction's ball tint and the star's string.
    private static let introBallYellow = Color(red: 0.98, green: 0.78, blue: 0.08)
    private static let introStarYellow = Color(red: 0.98, green: 0.84, blue: 0.15)
    /// buildWordLetters' palette, by the shuffled letter's position.
    private static let letterPalette: [Color] = [
        Color(red: 0.937, green: 0.325, blue: 0.314),
        Color(red: 0.671, green: 0.278, blue: 0.737),
        Color(red: 0.361, green: 0.420, blue: 0.753),
        Color(red: 0.161, green: 0.714, blue: 0.965),
        Color(red: 0.149, green: 0.651, blue: 0.604),
        Color(red: 0.400, green: 0.733, blue: 0.416),
        Color(red: 1.000, green: 0.792, blue: 0.157),
        Color(red: 1.000, green: 0.655, blue: 0.149),
        Color(red: 0.553, green: 0.431, blue: 0.388),
        Color(red: 0.471, green: 0.565, blue: 0.612)
    ]
    /// Which letterPalette colours are light (light blue, teal, green, amber, orange
    /// and blue grey) and take a navy letter.
    private static let letterPaletteIsLight: [Bool] = [
        false, false, false, true, true, true, true, true, false, true
    ]
    /// soccerStar1, 2, 3, 33, 11, 4, 5, 6 and 7 with their start delays.
    private static let goalStarLayout: [LanguageSoccerGoalStar] = [
        LanguageSoccerGoalStar(asset: 1, x: 0, y: 62, alignsRight: false, delay: 0.05),
        LanguageSoccerGoalStar(asset: 2, x: 0, y: 25, alignsRight: false, delay: 0.12),
        LanguageSoccerGoalStar(asset: 3, x: 0, y: 55, alignsRight: false, delay: 0),
        LanguageSoccerGoalStar(asset: 3, x: 0, y: -4, alignsRight: false, delay: 0.17),
        LanguageSoccerGoalStar(asset: 1, x: 42, y: -4, alignsRight: false, delay: 0.08),
        LanguageSoccerGoalStar(asset: 4, x: 18, y: 43, alignsRight: false, delay: 0.15),
        LanguageSoccerGoalStar(asset: 5, x: 42, y: 33, alignsRight: false, delay: 0.03),
        LanguageSoccerGoalStar(asset: 6, x: 0, y: 63, alignsRight: true, delay: 0.11),
        LanguageSoccerGoalStar(asset: 7, x: 42, y: 63, alignsRight: false, delay: 0.07)
    ]
}

/// release_line_dash: a horizontal line through the frame's middle.
private struct LanguageSoccerDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// mink_gate_pretty, the rainbow-sky design's glossy candy goal, drawn to the goal
/// rectangle: the pale net, the slanting back frame and, in front, the posts and
/// the crossbar as a pink-to-purple-to-blue tube with a soft shadow under it and a
/// shine along it. The front tube's outer edges lie on the rectangle, where the
/// collision posts are.
private struct LanguageSoccerCandyGoal: View {
    private static let pink = Color(red: 242 / 255, green: 92 / 255, blue: 162 / 255)
    private static let purple = Color(red: 164 / 255, green: 108 / 255, blue: 240 / 255)
    private static let blue = Color(red: 76 / 255, green: 155 / 255, blue: 234 / 255)
    private static let backPink = Color(red: 246 / 255, green: 168 / 255, blue: 207 / 255)
    private static let backPurple = Color(red: 201 / 255, green: 172 / 255, blue: 246 / 255)
    private static let backBlue = Color(red: 158 / 255, green: 202 / 255, blue: 242 / 255)
    private static let netInk = Color(red: 204 / 255, green: 194 / 255, blue: 240 / 255)

    var body: some View {
        GeometryReader { proxy in
            let tube = max(3, proxy.size.width * 0.05)
            let tubeStyle = StrokeStyle(lineWidth: tube, lineCap: .round, lineJoin: .round)
            ZStack {
                LanguageSoccerGoalNet(tube: tube)
                    .stroke(Self.netInk, lineWidth: max(1, tube * 0.14))
                    .clipShape(LanguageSoccerGoalNetArea(tube: tube))
                LanguageSoccerGoalBackFrame(tube: tube)
                    .stroke(
                        LinearGradient(
                            colors: [Self.backPink, Self.backPurple, Self.backBlue],
                            startPoint: UnitPoint.leading,
                            endPoint: UnitPoint.trailing
                        ),
                        style: StrokeStyle(lineWidth: tube * 0.7, lineCap: .round, lineJoin: .round)
                    )
                LanguageSoccerGoalFrontFrame(tube: tube)
                    .stroke(MinikPretty.navy.opacity(0.22), style: tubeStyle)
                    .offset(y: tube * 0.2)
                LanguageSoccerGoalFrontFrame(tube: tube)
                    .stroke(
                        LinearGradient(
                            colors: [Self.pink, Self.purple, Self.blue],
                            startPoint: UnitPoint.leading,
                            endPoint: UnitPoint.trailing
                        ),
                        style: tubeStyle
                    )
                LanguageSoccerGoalFrontFrame(tube: tube)
                    .stroke(
                        Color.white.opacity(0.5),
                        style: StrokeStyle(lineWidth: tube * 0.26, lineCap: .round, lineJoin: .round)
                    )
                    .offset(x: -tube * 0.14, y: -tube * 0.16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The goal's front: the two posts and the crossbar, their outer edges on the rectangle.
private struct LanguageSoccerGoalFrontFrame: Shape {
    let tube: CGFloat

    func path(in rect: CGRect) -> Path {
        let half = tube / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + half, y: rect.maxY - half))
        path.addLine(to: CGPoint(x: rect.minX + half, y: rect.minY + half))
        path.addLine(to: CGPoint(x: rect.maxX - half, y: rect.minY + half))
        path.addLine(to: CGPoint(x: rect.maxX - half, y: rect.maxY - half))
        return path
    }
}

/// The goal's back: the back posts slanting in from under the crossbar to the back
/// bar, and the ground braces from its ends out to the front posts' feet.
private struct LanguageSoccerGoalBackFrame: Shape {
    let tube: CGFloat

    func path(in rect: CGRect) -> Path {
        let half = tube / 2
        let backY = rect.minY + rect.height * 0.66
        let backLeft = rect.minX + rect.width * 0.17
        let backRight = rect.maxX - rect.width * 0.17
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY + tube))
        path.addLine(to: CGPoint(x: backLeft, y: backY))
        path.addLine(to: CGPoint(x: backRight, y: backY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + tube))
        path.move(to: CGPoint(x: backLeft, y: backY))
        path.addLine(to: CGPoint(x: rect.minX + half, y: rect.maxY - half))
        path.move(to: CGPoint(x: backRight, y: backY))
        path.addLine(to: CGPoint(x: rect.maxX - half, y: rect.maxY - half))
        return path
    }
}

/// The net's mesh: twelve columns and six rows across the goal.
private struct LanguageSoccerGoalNet: Shape {
    let tube: CGFloat

    func path(in rect: CGRect) -> Path {
        let columns = 12
        let rows = 6
        var path = Path()
        for column in 1 ..< columns {
            let x = rect.minX + rect.width * CGFloat(column) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: rect.minY + tube))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for row in 1 ..< rows {
            let y = rect.minY + tube + (rect.height - tube) * CGFloat(row) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// Where the net hangs: inside the front frame and down to the back bar, with the
/// side nets reaching the front posts' feet.
private struct LanguageSoccerGoalNetArea: Shape {
    let tube: CGFloat

    func path(in rect: CGRect) -> Path {
        let backY = rect.minY + rect.height * 0.66
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tube, y: rect.minY + tube))
        path.addLine(to: CGPoint(x: rect.maxX - tube, y: rect.minY + tube))
        path.addLine(to: CGPoint(x: rect.maxX - tube, y: rect.maxY - tube))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.17, y: backY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.17, y: backY))
        path.addLine(to: CGPoint(x: rect.minX + tube, y: rect.maxY - tube))
        path.closeSubpath()
        return path
    }
}

/// The string the introduction's star hangs from, slanting slightly.
private struct LanguageSoccerStarString: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// ConfettiRectView.start(3f) after a won match: small yellow and orange
/// rectangles fall from just above the screen for three seconds, growing a
/// little toward the bottom and fading out.
private struct LanguageSoccerConfetti: View {
    let startedAt: Date

    @Environment(\.scenePhase) private var scenePhase

    private static let palette: [Color] = [
        Color(red: 1.0, green: 0.757, blue: 0.027),
        Color(red: 1.0, green: 0.627, blue: 0.0),
        Color(red: 1.0, green: 0.718, blue: 0.302),
        Color(red: 1.0, green: 0.596, blue: 0.0),
        Color(red: 1.0, green: 0.439, blue: 0.263),
        Color(red: 1.0, green: 0.878, blue: 0.510)
    ]
    // 120 pieces a second for three seconds, about 240 on screen at once.
    private static let particleCount = 250
    private static let emittedPerSecond = 120.0
    // Android's 900 px/s² and 90-210 px/s at about 2.7 px per point.
    private static let gravity = 334.0

    var body: some View {
        let seed = UInt64(truncatingIfNeeded: Int64(startedAt.timeIntervalSinceReferenceDate * 1000))
        return TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                Self.drawParticles(
                    in: &context,
                    size: size,
                    elapsed: timeline.date.timeIntervalSince(startedAt),
                    seed: seed
                )
            }
        }
    }

    private static func drawParticles(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval,
        seed: UInt64
    ) {
        let width = Double(size.width)
        let height = max(1, Double(size.height))
        for index in 0 ..< particleCount {
            let age = elapsed - Double(index) / emittedPerSecond
            if age < 0 {
                break
            }
            let lifetime = 2.8 + 1.4 * unit(seed, index, 0)
            if age > lifetime {
                continue
            }
            let horizontalSpeed = (unit(seed, index, 1) - 0.5) * 44
            let verticalSpeed = 33 + 45 * unit(seed, index, 2)
            let x = width * unit(seed, index, 3) + horizontalSpeed * age
            let startY = -height * 0.15 * unit(seed, index, 4)
            let fallen = verticalSpeed * age + 0.5 * gravity * age * age
            let y = startY + fallen
            let base = 3 + 4 * unit(seed, index, 5)
            let stretch: Double
            if unit(seed, index, 6) < 0.35 {
                stretch = 1.8 + 1.4 * unit(seed, index, 7)
            } else {
                stretch = 0.9 + 0.7 * unit(seed, index, 7)
            }
            let depth = 0.6 + 0.7 * (y / height)
            let particleWidth = base * depth
            let particleHeight = base * stretch * depth
            if y - particleHeight > height {
                continue
            }
            let progress = age / lifetime
            let spin = (unit(seed, index, 9) - 0.5) * 540 * age
            let rotation = 360 * unit(seed, index, 8) + spin
            let colorIndex = Int(unit(seed, index, 10) * Double(palette.count)) % palette.count

            var particle = context
            particle.opacity = max(0, min(1, 1 - progress * progress))
            particle.translateBy(x: CGFloat(x), y: CGFloat(y))
            particle.rotate(by: .degrees(rotation))
            let rectangle = CGRect(
                x: -particleWidth / 2,
                y: -particleHeight / 2,
                width: particleWidth,
                height: particleHeight
            )
            particle.fill(
                Path(roundedRect: rectangle, cornerRadius: 2),
                with: .color(palette[colorIndex])
            )
        }
    }

    /// A stable pseudo-random value in 0..<1 for one particle property, so a
    /// redraw never reshuffles the confetti.
    private static func unit(_ seed: UInt64, _ index: Int, _ channel: UInt64) -> Double {
        var value = seed
        value = value &+ UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15
        value = value &+ channel &* 0xD1B5_4A32_D192_ED03
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value = value ^ (value >> 31)
        return Double(value >> 11) / 9_007_199_254_740_992.0
    }
}

private extension View {
    /// Android's fake bold for Fredoka Medium (textStyle="bold" on a font without a
    /// bold face): crisp offset copies thicken every stroke without changing layout.
    @ViewBuilder
    func soccerFakeBold(_ color: Color, spread: CGFloat) -> some View {
        if spread > 0 {
            self
                .shadow(color: color, radius: 0, x: spread, y: 0)
                .shadow(color: color, radius: 0, x: -spread, y: 0)
                .shadow(color: color, radius: 0, x: 0, y: spread)
                .shadow(color: color, radius: 0, x: 0, y: -spread)
        } else {
            self
        }
    }
}
