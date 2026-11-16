import SwiftUI

/// Learned-language words that never break inside a word (owner QA, 16 November 2026, issues 11
/// and 15: "Anthropologist" showed as "Anthropologi" / "st"). SwiftUI wraps a word that is wider
/// than the line letter by letter, and `minimumScaleFactor` does not shrink the text while the
/// broken lines still fit its line limit. So:
///
/// - A single word keeps one line and shrinks to the width.
/// - Text with spaces may wrap, but only between words. The largest size whose widest word fits on
///   one line is chosen (`ViewThatFits` measures each size by its widest word). Within that size,
///   `minimumScaleFactor` still shrinks the text when it needs more lines than allowed.
///
/// Hebrew and Arabic keep their direction from the environment, as before.
struct LanguageWholeWordsText: View {
    let text: String
    let fontSize: CGFloat
    let font: (CGFloat) -> Font
    /// Lines a phrase may take; nil lets it take as many as it needs (accessibility sizes).
    let maxLines: Int?
    /// The text grows vertically instead of keeping to its row (accessibility sizes).
    let growsVertically: Bool
    let minimumScaleFactor: CGFloat

    /// Font sizes tried for a phrase, as fractions of `fontSize`, largest first.
    private static let phraseScales: [CGFloat] = [1, 0.85, 0.72, 0.6, 0.5, 0.42, 0.35]

    init(
        text: String,
        fontSize: CGFloat,
        font: @escaping (CGFloat) -> Font,
        maxLines: Int?,
        growsVertically: Bool = false,
        minimumScaleFactor: CGFloat = 0.35
    ) {
        self.text = text
        self.fontSize = fontSize
        self.font = font
        self.maxLines = maxLines
        self.growsVertically = growsVertically
        self.minimumScaleFactor = minimumScaleFactor
    }

    var body: some View {
        if words.count <= 1 {
            Text(verbatim: text)
                .font(font(fontSize))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(minimumScaleFactor)
        } else {
            ViewThatFits(in: .horizontal) {
                phrase(scale: Self.phraseScales[0])
                phrase(scale: Self.phraseScales[1])
                phrase(scale: Self.phraseScales[2])
                phrase(scale: Self.phraseScales[3])
                phrase(scale: Self.phraseScales[4])
                phrase(scale: Self.phraseScales[5])
                phrase(scale: Self.phraseScales[6])
                // Only for a word too long even at the smallest size.
                phraseText(size: fontSize * Self.phraseScales[6])
            }
        }
    }

    /// The words of the text, split at spaces.
    var words: [String] {
        Self.words(in: text)
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The phrase at `fontSize * scale`. Its ideal width is its widest word on one line, so
    /// `ViewThatFits` takes it only when every word fits the line whole; laid out, it takes the
    /// width it is offered and wraps between words.
    private func phrase(scale: CGFloat) -> some View {
        let size = fontSize * scale
        return ZStack {
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    Text(verbatim: word)
                        .font(font(size))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(height: 0)
            .hidden()
            .accessibilityHidden(true)

            phraseText(size: size)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
        }
    }

    private func phraseText(size: CGFloat) -> some View {
        Text(verbatim: text)
            .font(font(size))
            .multilineTextAlignment(.center)
            .lineLimit(maxLines)
            .minimumScaleFactor(minimumScaleFactor)
            .fixedSize(horizontal: false, vertical: growsVertically)
    }
}
