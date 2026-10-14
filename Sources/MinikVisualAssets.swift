import SwiftUI

enum MinikVisualAsset {
    static let background = "minik_background"
    /// The product's logo inside the app (Parent Area, Remove Ads): the MINIK+plus badge
    /// in both language apps (Android's Remove Ads dialog and reminder show
    /// minik_logo_pretty_plus in English Only too) and the new Minik Math logo in Math, as
    /// Android's pretty design shows them; the pencil mascot in the other apps.
    static let logo: String = {
        #if MINIK_MATH
        return MinikPretty.Art.mathLogo
        #elseif MINIK_PLUS || MINIK_PLUS_ENGLISH
        return MinikPretty.Art.plusLogo
        #else
        return "minik_logo"
        #endif
    }()
    static let home = "minik_home"
    static let trophy = "minik_trophy"
    static let close = "minik_close"
    static let speaker = "minik_speaker"
    static let welcome = "minik_welcome"
    static let success = "minik_feedback_success"
    static let tryAgain = "minik_feedback_try_again"
    static let soccerField = "minik_soccer_field"
    static let soccerGoal = "minik_soccer_goal"
    static let soccerGoalie = "minik_soccer_goalie"
    static let soccerBall = "minik_soccer_ball"
    static let towerMascot = "minik_tower_mascot"
    static let towerSand = "minik_tower_sand"
    static let towerSandPile = "minik_tower_sand_pile"
    static let towerScene = "minik_tower_scene"
    // SoccerIntroDialog selects the same Android plus_background pixels for Plus.
    static let soccerIntroScene = towerScene
    static let cardsBackground = "minik_cards_background"
    static let cardsMascot = "minik_activity_mixed"
    static let memoryMascot = "minik_memory_mascot"
    static let memoryScene = "minik_memory_scene"
    static let ticTacToeMascot = "minik_tic_tac_toe_mascot"
    static let ticTacToeScene = "minik_tic_tac_toe_scene"
    private static let activityLearnEnglish = "minik_activity_learn_english"
    private static let activityLearnHebrew = "minik_activity_learn_hebrew"
    private static let activityFirstLetterEnglish = "minik_activity_first_letter_english"
    private static let activityFirstLetterHebrew = "minik_activity_first_letter_hebrew"
    private static let activityBuildEnglish = "minik_activity_build"
    private static let activityBuildHebrew = "minik_activity_build_hebrew"
    private static let activityCardsEnglish = "minik_activity_cards"
    private static let activityCardsHebrew = "minik_activity_cards_hebrew"
    private static let activityPictureToWord = "minik_activity_picture_to_word"
    private static let activityWordToPicture = "minik_activity_word_to_picture"

    static func activityArtwork(
        for activity: LanguageActivityKind,
        language: LanguageIdentifier
    ) -> String? {
        switch activity {
        case .learn:
            return language == .hebrew
                ? activityLearnHebrew
                : activityLearnEnglish
        case .letterPairs:
            return "minik_activity_pairs"
        case .firstLetterChoices, .firstLetterPictures:
            return language == .hebrew
                ? activityFirstLetterHebrew
                : activityFirstLetterEnglish
        case .imageToWord:
            return activityPictureToWord
        case .wordToImage:
            return activityWordToPicture
        case .wordBuild:
            return language == .hebrew
                ? activityBuildHebrew
                : activityBuildEnglish
        case .mixed:
            return "minik_activity_mixed"
        case .wordCards:
            return language == .hebrew
                ? activityCardsHebrew
                : activityCardsEnglish
        case .soccer:
            return "minik_activity_soccer"
        case .tower:
            return "minik_activity_tower"
        case .wordMemory:
            return "minik_activity_memory"
        case .ticTacToe:
            return "minik_activity_tic_tac_toe"
        case .multipleChoice, .build, .pairs, .memory:
            return nil
        }
    }
}

struct MinikArtworkImage: View {
    let name: String
    var contentMode: ContentMode = .fit

    var body: some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .accessibilityHidden(true)
    }
}

struct MinikArtworkBackground: View {
    var body: some View {
        MinikArtworkImage(name: MinikVisualAsset.background, contentMode: .fill)
            .ignoresSafeArea()
            .overlay(Color.white.opacity(0.08).ignoresSafeArea())
            .clipped()
            .accessibilityHidden(true)
    }
}
