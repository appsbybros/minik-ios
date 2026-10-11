import AVFoundation
import Combine

struct LearningSpeechUtterance: Hashable, Sendable {
    let text: String
    let language: LanguageIdentifier
}

extension LearningTextRepresentation {
    var learningSpeechCue: LearningSpeechUtterance? {
        guard let language,
              !(speechText ?? text).isEmpty else {
            return nil
        }
        return LearningSpeechUtterance(
            text: speechText ?? text,
            language: language
        )
    }
}

extension Representation {
    var learningSpeechCue: LearningSpeechUtterance? {
        guard case .learningText(let text) = self else {
            return nil
        }
        return text.learningSpeechCue
    }
}

struct LearningSpeechPlan: Equatable, Sendable {
    let utterances: [LearningSpeechUtterance]

    init(card: StudyCard) {
        utterances = card.representations.compactMap { representation in
            guard case .learningText(let text) = representation,
                  let language = text.language else {
                return nil
            }
            return LearningSpeechUtterance(
                text: text.speechText ?? text.text,
                language: language
            )
        }
    }
}

enum LearningSpeechVoiceLocale {
    static func identifier(for language: LanguageIdentifier) -> String {
        switch language {
        case .english:
            "en-US"
        case .hebrew:
            "he-IL"
        default:
            language.rawValue
        }
    }
}

/// Apple's voices read a lone capital letter as "Capital D". The letter
/// activities show capitals only and never teach the difference, so a lone
/// letter is handed to the voice in lowercase, which it reads as the bare
/// letter name ("D"), as Android's voice says it and as Learn already does
/// ("a" for "A a"). Only the spoken copy changes; screens keep the capitals.
/// Words and sentences are left as they are, and so are caseless letters
/// (Hebrew).
enum LearningSpeechLetterName {
    static func spokenText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1,
              let letter = trimmed.first,
              letter.isLetter,
              letter.isUppercase else {
            return text
        }
        return trimmed.lowercased()
    }
}

@MainActor
final class LearningSpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var queue = LearningSpeechQueueState()
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ plan: LearningSpeechPlan) { speak(plan.utterances) }
    func speak(_ utterance: LearningSpeechUtterance) { speak([utterance]) }

    /// Every letter, word and prompt of the learning screens is said here: a lone
    /// letter by its name only (LearningSpeechLetterName), never "Capital D".
    func speak(_ utterances: [LearningSpeechUtterance]) {
        stop()
        for item in utterances where !item.text.isEmpty {
            let utterance = AVSpeechUtterance(string: LearningSpeechLetterName.spokenText(item.text))
            utterance.voice = AVSpeechSynthesisVoice(language: LearningSpeechVoiceLocale.identifier(for: item.language))
            enqueue(utterance)
        }
    }

    /// One queue preserves learned-word / host-encouragement ordering. Only the
    /// spoken copy gets the locale's pronunciation fixes (HebrewSpeechPronunciation).
    func enqueueInterfaceSpeech(_ text: String, interfaceLocale: InterfaceLocaleID) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: LearningSpeechLetterName.spokenText(
            interfaceLocale.spokenText(for: text)
        ))
        utterance.voice = AVSpeechSynthesisVoice(language: interfaceLocale.rawValue)
            ?? AVSpeechSynthesisVoice(language: interfaceLocale.locale.language.languageCode?.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        enqueue(utterance)
    }

    func enqueuePracticeEncouragement(cleanRun: Int, interfaceLocale: InterfaceLocaleID) {
        if cleanRun >= 3 {
            let number = cleanRun.formatted(.number.locale(interfaceLocale.locale))
            enqueueInterfaceSpeech(number + " " + interfaceLocale.text("correct answers in a row"), interfaceLocale: interfaceLocale)
            enqueueInterfaceSpeech(interfaceLocale.text(LanguageWordEncouragement.suffix(for: cleanRun)), interfaceLocale: interfaceLocale)
        } else if let phrase = LanguageWordEncouragement.ordinary.randomElement() {
            enqueueInterfaceSpeech(interfaceLocale.text(phrase), interfaceLocale: interfaceLocale)
        }
    }

    /// Automatic progression waits for real utterance completion, including
    /// queued encouragement. Explicit replay/exit may still interrupt immediately.
    func waitUntilFinished() async {
        guard !queue.pending.isEmpty, !Task.isCancelled else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append(continuation)
        }
    }

    func stop() {
        // Clear identities before stop: delayed cancellation callbacks for the
        // previous queue must never finish a newer queue or its waiting task.
        queue.cancelAll()
        synthesizer.stopSpeaking(at: .immediate)
        resumeCompletionWaiters()
    }

    private func enqueue(_ utterance: AVSpeechUtterance) {
        queue.enqueue(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    private func finished(_ id: ObjectIdentifier) {
        guard queue.finish(id) else { return }
        resumeCompletionWaiters()
    }

    private func resumeCompletionWaiters() {
        let pending = completionWaiters
        completionWaiters.removeAll()
        for continuation in pending { continuation.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
}
