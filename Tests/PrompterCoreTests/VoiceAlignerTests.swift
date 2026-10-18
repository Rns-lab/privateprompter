import XCTest
@testable import PrompterCore

final class VoiceAlignerTests: XCTestCase {
    func testNormalizationPreservesWordsAndRanges() {
        let document = ScriptDocument(text: "Perché l'AI è già qui — davvero.")
        XCTAssertEqual(document.words.map(\.normalized), ["perche", "lai", "e", "gia", "qui", "davvero"])
        XCTAssertEqual((document.text as NSString).substring(with: document.words[0].range), "Perché")
    }

    func testExactSpeechAdvances() {
        let aligner = VoiceAligner(text: "uno due tre quattro cinque sei sette")
        XCTAssertEqual(aligner.align(transcript: "uno due tre quattro"), 3)
        XCTAssertEqual(aligner.align(transcript: "uno due tre quattro cinque sei"), 5)
    }

    func testInsertionsAndSkippedWordsAreTolerated() {
        let aligner = VoiceAligner(text: "oggi vediamo tre modi semplici per migliorare il lavoro")
        let index = aligner.align(transcript: "oggi vediamo in pratica tre modi per migliorare il lavoro")
        XCTAssertGreaterThanOrEqual(index, 7)
    }

    func testShortCommonWordCannotCauseLongJump() {
        let aligner = VoiceAligner(text: "io sono qui e questo è un testo molto lungo che poi usa ancora la parola qui")
        XCTAssertLessThanOrEqual(aligner.align(transcript: "qui"), 3)
    }

    func testExplicitJumpCanMoveBackward() {
        let aligner = VoiceAligner(text: "uno due tre quattro cinque")
        _ = aligner.align(transcript: "uno due tre quattro cinque")
        XCTAssertEqual(aligner.jump(to: 1), 1)
    }

    func testRepeatedPhraseDoesNotCauseArbitraryForwardJump() {
        let text = "inizio chiaro del discorso poi continuiamo con altri concetti e molte parole "
            + "prima di ripetere inizio chiaro del discorso molto più avanti"
        let aligner = VoiceAligner(text: text)
        XCTAssertLessThanOrEqual(
            aligner.align(transcript: "inizio chiaro del discorso", sessionID: 1),
            5
        )
    }

    func testNewRecognitionSessionContinuesNearCurrentPosition() {
        let aligner = VoiceAligner(text: "uno due tre quattro cinque sei sette otto nove dieci")
        XCTAssertEqual(aligner.align(transcript: "uno due tre quattro", sessionID: 1), 3)
        XCTAssertGreaterThanOrEqual(aligner.align(transcript: "cinque sei sette", sessionID: 2), 6)
    }

    func testSpeechLeadCompensatesRecognitionDelay() {
        XCTAssertEqual(
            SpeechLeadEstimator.leadWords(
                segmentCount: 10,
                lastSegmentEnd: 4,
                audioElapsed: 5.2,
                isFinal: false
            ),
            3
        )
    }

    func testSpeechLeadIsBoundedAndStopsOnFinalResult() {
        XCTAssertEqual(
            SpeechLeadEstimator.leadWords(
                segmentCount: 20,
                lastSegmentEnd: 5,
                audioElapsed: 12,
                isFinal: false
            ),
            4
        )
        XCTAssertEqual(
            SpeechLeadEstimator.leadWords(
                segmentCount: 20,
                lastSegmentEnd: 5,
                audioElapsed: 12,
                isFinal: true
            ),
            0
        )
    }

    func testFinalSpeechResultReconcilesPredictedCursor() {
        XCTAssertEqual(
            SpeechLeadEstimator.displayedIndex(
                currentDisplayedIndex: 18,
                confirmedIndex: 14,
                leadWords: 0,
                lastIndex: 100,
                isFinal: true
            ),
            14
        )
        XCTAssertEqual(
            SpeechLeadEstimator.displayedIndex(
                currentDisplayedIndex: 14,
                confirmedIndex: 14,
                leadWords: 3,
                lastIndex: 100,
                isFinal: false
            ),
            17
        )
    }
}
