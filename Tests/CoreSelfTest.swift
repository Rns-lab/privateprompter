import Foundation
import Darwin
#if !PROMPTER_STANDALONE
import PrompterCore
#endif

@main
enum CoreSelfTest {
    static func main() {
        trace("start")
        expect(ScriptDocument.normalize("Perché") == "perche", "normalizzazione accenti")

        trace("exact")
        let exact = VoiceAligner(text: "uno due tre quattro cinque sei sette")
        expect(exact.align(transcript: "uno due tre quattro") == 3, "allineamento esatto")
        expect(exact.align(transcript: "uno due tre quattro cinque sei") == 5, "avanzamento progressivo")

        trace("flexible")
        let flexible = VoiceAligner(text: "oggi vediamo tre modi semplici per migliorare il lavoro")
        expect(
            flexible.align(transcript: "oggi vediamo in pratica tre modi per migliorare il lavoro") >= 7,
            "tolleranza a parole aggiunte e saltate"
        )

        trace("guarded")
        let guarded = VoiceAligner(text: "io sono qui e questo è un testo molto lungo che poi usa ancora la parola qui")
        expect(guarded.align(transcript: "qui") <= 3, "protezione dai falsi salti")

        trace("latency compensation")
        expect(
            SpeechLeadEstimator.leadWords(
                segmentCount: 10,
                lastSegmentEnd: 4,
                audioElapsed: 5.2,
                isFinal: false
            ) == 3,
            "compensazione dinamica del ritardo"
        )
        expect(
            SpeechLeadEstimator.leadWords(
                segmentCount: 20,
                lastSegmentEnd: 5,
                audioElapsed: 12,
                isFinal: false
            ) == 4,
            "limite della previsione"
        )
        expect(
            SpeechLeadEstimator.leadWords(
                segmentCount: 20,
                lastSegmentEnd: 5,
                audioElapsed: 12,
                isFinal: true
            ) == 0,
            "nessuna previsione sul risultato finale"
        )

        expect(
            SpeechLeadEstimator.displayedIndex(
                currentDisplayedIndex: 18,
                confirmedIndex: 14,
                leadWords: 0,
                lastIndex: 100,
                isFinal: true
            ) == 14,
            "riconciliazione del cursore a fine frase"
        )

        let repeated = VoiceAligner(
            text: "inizio chiaro del discorso poi continuiamo con altri concetti e molte parole "
                + "prima di ripetere inizio chiaro del discorso molto più avanti"
        )
        expect(
            repeated.align(transcript: "inizio chiaro del discorso", sessionID: 1) <= 5,
            "nessun salto su una frase ripetuta"
        )

        let sessions = VoiceAligner(text: "uno due tre quattro cinque sei sette otto nove dieci")
        expect(
            sessions.align(transcript: "uno due tre quattro", sessionID: 1) == 3,
            "prima sessione"
        )
        expect(
            sessions.align(transcript: "cinque sei sette", sessionID: 2) >= 6,
            "continuità tra sessioni"
        )

        expect(
            SpeechStallDetector.shouldRestart(now: 10, lastResult: 7, lastSpeech: 9.5),
            "watchdog riavvia durante voce attiva"
        )
        expect(
            !SpeechStallDetector.shouldRestart(now: 10, lastResult: 7, lastSpeech: 7),
            "watchdog non riavvia durante silenzio"
        )
        expect(
            !SpeechStallDetector.shouldRestart(now: 10, lastResult: 9, lastSpeech: 9.5),
            "watchdog non riavvia prematuramente"
        )

        // 80 distinct short words: too short for the aligner's typo tolerance.
        let syllables = ["ba", "ce", "di", "fo", "gu", "la", "me", "ni", "po", "ru"]
        let endings = ["to", "sa", "ve", "mi", "lo", "re", "pa", "nu"]
        let vocabulary = endings.flatMap { end in syllables.map { $0 + end } }
        let skipped = VoiceAligner(text: vocabulary.joined(separator: " "))
        _ = skipped.align(transcript: vocabulary[0...2].joined(separator: " "), sessionID: 1)
        expect(
            skipped.align(transcript: (vocabulary[0...2] + vocabulary[59...64]).joined(separator: " "), sessionID: 1) == 64,
            "ritrova il punto dopo un paragrafo saltato"
        )

        let restarted = VoiceAligner(text: vocabulary.joined(separator: " "))
        _ = restarted.align(transcript: vocabulary[0...29].joined(separator: " "), sessionID: 1)
        expect(
            restarted.align(transcript: vocabulary[30...32].joined(separator: " "), sessionID: 1) == 32,
            "trascrizione ricominciata dopo una pausa"
        )

        print("CoreSelfTest: 16/16 OK")
    }

    private static func trace(_ message: String) {
        FileHandle.standardError.write(Data("CoreSelfTest: \(message)\n".utf8))
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            trace("FALLITO: \(message)")
            exit(1)
        }
    }
}
