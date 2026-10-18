import Foundation

public struct ScriptWord: Equatable, Sendable {
    public let text: String
    public let normalized: String
    public let range: NSRange

    public init(text: String, normalized: String, range: NSRange) {
        self.text = text
        self.normalized = normalized
        self.range = range
    }
}

public struct ScriptDocument: Sendable {
    public let text: String
    public let words: [ScriptWord]

    public init(text: String) {
        self.text = text
        self.words = Self.tokenizeWithRanges(text)
    }

    public func wordIndex(containingUTF16Location location: Int) -> Int? {
        guard !words.isEmpty else { return nil }

        if let exact = words.firstIndex(where: { NSLocationInRange(location, $0.range) }) {
            return exact
        }

        return words.enumerated().min(by: { lhs, rhs in
            abs(lhs.element.range.location - location) < abs(rhs.element.range.location - location)
        })?.offset
    }

    /// Distinctive script words (names, jargon) handed to Apple Speech as hints.
    public var contextualWords: [String] {
        var seen = Set<String>()
        return Array(words.compactMap { word in
            guard word.normalized.count >= 5, seen.insert(word.normalized).inserted else { return nil }
            return word.text
        }.prefix(100))
    }

    public static func normalizedTokens(from text: String) -> [String] {
        tokenizeWithRanges(text).map(\.normalized)
    }

    public static func normalize(_ token: String) -> String {
        let folded = token
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        return folded.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func tokenizeWithRanges(_ text: String) -> [ScriptWord] {
        var output: [ScriptWord] = []
        let fullRange = text.startIndex..<text.endIndex

        text.enumerateSubstrings(in: fullRange, options: [.byWords, .localized]) { substring, range, _, _ in
            guard let substring else { return }
            let normalized = normalize(substring)
            guard !normalized.isEmpty else { return }

            output.append(
                ScriptWord(
                    text: substring,
                    normalized: normalized,
                    range: NSRange(range, in: text)
                )
            )
        }

        return output
    }
}
