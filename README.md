# Private Prompter

Utility macOS privata: pannello teleprompter sempre in primo piano, riconoscimento
vocale Apple on-device e finestra esclusa da condivisioni e registrazioni tramite
`NSWindow.sharingType = .none`.

## Uso

1. Apri `Private Prompter.app`.
2. Incolla il copione nell'editor oppure scegli **Carica dagli appunti**.
3. Lascia attivo **Invisibile in condivisioni e registrazioni**.
4. Premi **Mostra e ascolta** e autorizza Microfono e Riconoscimento vocale.
5. Trascina e ridimensiona il pannello. Clicca una parola per ripartire da lì.

L'audio non viene registrato o salvato. Il riconoscimento è forzato in modalità
on-device; se il modello Apple non è disponibile per la lingua scelta, l'app non
ripiega su servizi di rete.

## Primo test consigliato

Avvia una registrazione QuickTime o una condivisione Zoom/Meet, mantenendo il
pannello visibile sul tuo schermo. Controlla l'anteprima: il pannello deve essere
assente. La voce **Invisibile...** permette di disattivare la protezione per fare
un confronto immediato.

## Compilazione

```bash
./build.sh /percorso/output
```

Richiede macOS 15 o successivo e gli Apple Command Line Tools. Non richiede
dipendenze esterne né pubblicazione sull'App Store.

## Test

```bash
# test del nucleo, senza Xcode (16 controlli)
swiftc -D PROMPTER_STANDALONE -parse-as-library Sources/PrompterCore/*.swift Tests/CoreSelfTest.swift -o selftest && ./selftest
# test XCTest, richiede Xcode completo (con i soli Command Line Tools XCTest non c'è)
swift test
```

## Limiti noti

- L'invisibilità usa `NSWindow.sharingType = .none`: dipende da come l'app di cattura legge lo schermo e dalla versione di macOS. Fai sempre il "Primo test consigliato" qui sopra prima di fidarti.
- Verificato su macOS 26.6 registrando lo schermo con [Recordly](https://github.com/webadderallorg/Recordly): la registrazione cattura lo schermo e il pannello non compare. Non testato con altre app di cattura (QuickTime, Zoom, Meet, OBS).
- Il testo del copione e la trascrizione restano in locale; l'app non apre connessioni di rete.

## Misurare il tracciamento

```bash
# 1. registrazione vera -> ipotesi di Apple Speech (chiede il permesso Riconoscimento vocale)
open -W -n "/Applications/Private Prompter.app" --args --replay audio.wav copione.txt out.csv
# 2. offline, senza riconoscitore: si rilancia a ogni modifica dell'allineamento
swiftc -D PROMPTER_STANDALONE -parse-as-library Sources/PrompterCore/*.swift Tests/OfflineReplay.swift -o offline
./offline out.csv.jsonl copione.txt > cursore.csv
```

`out.csv.jsonl` contiene il testo trascritto: resta in locale, non va condiviso.
L'app è firmata ad-hoc: dopo ogni ricompilazione macOS richiede di nuovo i permessi.

## Licenza

MIT, vedi [LICENSE](LICENSE).
