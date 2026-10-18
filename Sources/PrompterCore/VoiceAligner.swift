import Foundation

public final class VoiceAligner {
    public private(set) var document: ScriptDocument
    public private(set) var currentIndex: Int
    private var activeSessionID: Int?
    private var sessionAnchorIndex: Int
    /// Words already in the session transcript when the anchor was set: after a
    /// click mid-session, only words spoken since then count toward the expectation.
    private var sessionSpokenBase = 0
    private var jumpedFromSessionID: Int?
    private var lastSpokenCount = 0

    public init(text: String, startAt index: Int = 0) {
        document = ScriptDocument(text: text)
        currentIndex = Self.clamp(index, count: document.words.count)
        sessionAnchorIndex = currentIndex
    }

    public func replaceScript(_ text: String, startAt index: Int = 0) {
        document = ScriptDocument(text: text)
        currentIndex = Self.clamp(index, count: document.words.count)
        activeSessionID = nil
        jumpedFromSessionID = nil
        sessionAnchorIndex = currentIndex
    }

    @discardableResult
    public func jump(to index: Int) -> Int {
        currentIndex = Self.clamp(index, count: document.words.count)
        jumpedFromSessionID = activeSessionID
        activeSessionID = nil
        sessionAnchorIndex = currentIndex
        return currentIndex
    }

    /// Aligns the latest recognition hypothesis to a bounded area of the script.
    /// The comparison deliberately tolerates inserted words, skipped words and
    /// small recognition mistakes while requiring stronger evidence for long jumps.
    @discardableResult
    public func align(transcript: String) -> Int {
        align(transcript: transcript, sessionID: 0)
    }

    /// Aligns a hypothesis within one Apple Speech session. The session anchor
    /// makes the expected script position grow with the recognized word count,
    /// preventing a repeated phrase from causing an arbitrary forward jump.
    @discardableResult
    public func align(transcript: String, sessionID: Int) -> Int {
        let spoken = ScriptDocument.normalizedTokens(from: transcript)
        let script = document.words.map(\.normalized)
        guard !spoken.isEmpty, !script.isEmpty else { return currentIndex }

        // Apple Speech restarts the hypothesis after a pause while keeping the
        // same task: the transcript shrinks to the new utterance. Treat that as
        // a new session, or the expected position falls far behind the reader.
        let transcriptRestarted = activeSessionID == sessionID && spoken.count + 3 < lastSpokenCount
        lastSpokenCount = spoken.count

        if activeSessionID != sessionID || transcriptRestarted {
            // A new session starts with an empty transcript; a jump inside a
            // running session re-anchors at the words heard so far, minus the
            // one this partial may have just added.
            sessionSpokenBase = sessionID == jumpedFromSessionID ? max(0, spoken.count - 1) : 0
            activeSessionID = sessionID
            sessionAnchorIndex = currentIndex
        }
        jumpedFromSessionID = nil

        let maximumSuffix = min(14, spoken.count)
        let searchStart = max(0, currentIndex - 3)
        let expectedEndIndex = min(script.count - 1, sessionAnchorIndex + spoken.count - sessionSpokenBase - 1)
        let searchEnd = min(script.count, max(currentIndex + 4, expectedEndIndex + 13))

        var best: Candidate?
        // How well the newest words (the suffix `relocate` uses) match locally.
        let relocationSuffix = min(6, spoken.count)
        var bestRelocationSuffixSimilarity = 0.0

        for suffixLength in 1...maximumSuffix {
            let spokenSuffix = Array(spoken.suffix(suffixLength))
            let minimumScriptLength = max(1, suffixLength - 3)
            let maximumScriptLength = suffixLength + 3

            for end in (searchStart + 1)...searchEnd {
                for scriptLength in minimumScriptLength...maximumScriptLength {
                    let start = end - scriptLength
                    guard start >= searchStart else { continue }

                    let scriptSlice = Array(script[start..<end])
                    let distance = Self.weightedEditDistance(spokenSuffix, scriptSlice)
                    let denominator = Double(max(spokenSuffix.count, scriptSlice.count))
                    let similarity = max(0, 1 - distance / denominator)

                    let forwardDistance = max(0, end - currentIndex - 1)
                    let expectedDistance = abs((end - 1) - expectedEndIndex)
                    let evidenceBonus = Double(min(suffixLength, 8)) * 0.025
                    let jumpPenalty = Double(forwardDistance) * 0.0025
                    let expectationPenalty = Double(expectedDistance) * 0.022
                    let score = similarity + evidenceBonus - jumpPenalty - expectationPenalty
                    let candidate = Candidate(
                        endIndex: end - 1,
                        suffixLength: suffixLength,
                        similarity: similarity,
                        score: score
                    )

                    if suffixLength == relocationSuffix {
                        bestRelocationSuffixSimilarity = max(bestRelocationSuffixSimilarity, similarity)
                    }
                    if best == nil || candidate.score > best!.score {
                        best = candidate
                    }
                }
            }
        }

        // The newest words match nothing nearby: the reader may have skipped ahead.
        if bestRelocationSuffixSimilarity < 0.6,
           let relocated = relocate(spoken: spoken, script: script, after: searchEnd) {
            currentIndex = relocated
            sessionAnchorIndex = relocated
            sessionSpokenBase = spoken.count - 1
            return currentIndex
        }

        guard let best, Self.isConfident(best, currentIndex: currentIndex) else {
            return currentIndex
        }

        // A strong match can correct a small prediction overshoot. Larger
        // backwards movements remain an explicit click action.
        if best.endIndex < currentIndex,
           currentIndex - best.endIndex <= 4,
           best.similarity >= 0.82 {
            currentIndex = best.endIndex
        } else {
            currentIndex = max(currentIndex, best.endIndex)
        }
        return currentIndex
    }

    /// The reader skipped beyond the local window (a paragraph, a page): look
    /// for the last few spoken words in the rest of the script. Only a long,
    /// near-exact match moves the cursor, and the nearest one wins.
    private func relocate(spoken: [String], script: [String], after searchEnd: Int) -> Int? {
        let suffixLength = min(6, spoken.count)
        guard suffixLength >= 6, searchEnd < script.count else { return nil }
        let suffix = Array(spoken.suffix(suffixLength))

        for end in (searchEnd + 1)...script.count {
            let start = end - suffixLength
            guard start >= 0 else { continue }
            let distance = Self.weightedEditDistance(suffix, Array(script[start..<end]))
            if 1 - distance / Double(suffixLength) >= 0.8 { return end - 1 }  // one error in six
        }
        return nil
    }

    private static func isConfident(_ candidate: Candidate, currentIndex: Int) -> Bool {
        let jump = max(0, candidate.endIndex - currentIndex)

        if candidate.suffixLength == 1 {
            return candidate.similarity >= 0.999 && jump <= 3
        }

        if candidate.suffixLength <= 3 {
            return candidate.similarity >= 0.72 && jump <= 20
        }

        if jump > 45 {
            return candidate.similarity >= 0.78
        }

        return candidate.similarity >= 0.58
    }

    private static func weightedEditDistance(_ lhs: [String], _ rhs: [String]) -> Double {
        guard !lhs.isEmpty else { return Double(rhs.count) }
        guard !rhs.isEmpty else { return Double(lhs.count) }

        var previous = (0...rhs.count).map(Double.init)

        for i in 1...lhs.count {
            var current = Array(repeating: 0.0, count: rhs.count + 1)
            current[0] = Double(i)

            for j in 1...rhs.count {
                let substitution = previous[j - 1] + tokenSubstitutionCost(lhs[i - 1], rhs[j - 1])
                let deletion = previous[j] + 1
                let insertion = current[j - 1] + 1
                current[j] = min(substitution, deletion, insertion)
            }

            previous = current
        }

        return previous[rhs.count]
    }

    private static func tokenSubstitutionCost(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 0 }
        if lhs.count >= 5, rhs.count >= 5, characterDistance(lhs, rhs) <= 1 { return 0.25 }
        if lhs.count >= 7, rhs.count >= 7, characterDistance(lhs, rhs) <= 2 { return 0.4 }
        return 1
    }

    private static func characterDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for i in 1...left.count {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = i

            for j in 1...right.count {
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                )
            }

            previous = current
        }

        return previous[right.count]
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, index), count - 1)
    }

    private struct Candidate {
        let endIndex: Int
        let suffixLength: Int
        let similarity: Double
        let score: Double
    }
}
