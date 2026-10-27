# Isola Clipboard 1.0.0

Applicazione personale per macOS, realizzata in SwiftUI e AppKit. La cronologia vive solo nella memoria del processo; non ci sono servizi cloud o telemetria.

## Pacchetto

Apri `IsolaClipboard.xcodeproj` con Xcode oppure usa gli script inclusi. Per generare un bundle di rilascio arm64:

```sh
sh scripts/package-release.sh
```

Il bundle risultante è `release/Isola Clipboard.app`. Le build locali e i bundle di rilascio sono esclusi da Git. Il pacchetto è arm64, versione 1.0.0 e firmato ad hoc; non è notarizzato per la distribuzione a terzi.

## Uso e preferenze

- L’icona monocromatica `document.on.clipboard` apre il menu per mostrare/nascondere l’isola, aprire Impostazioni, svuotare la cronologia con conferma o uscire.
- La scorciatoia predefinita è `⌃⌥Spazio`; `⌃⌥,` apre Impostazioni anche se l’icona menu è nascosta.
- La cronologia contiene da uno a cinque elementi in una riga compatta. Testi, URL, immagini e file si possono ricopiare o trascinare. I file usano il loro URL originale.
- Il timeout predefinito è di 2 secondi e si può impostare da 1 a 10. L’opzione **Chiudi al clic esterno** si può attivare o disattivare.
- Le impostazioni includono avvio al login tramite `SMAppService.mainApp`, icona menu, limite cronologia, apertura dopo copia, scorciatoia, tema, animazioni e filtri privacy. macOS può richiedere l’approvazione esplicita del login item.
- I contenuti contrassegnati come riservati o temporanei sono esclusi quando riconoscibili. La cronologia non viene salvata su disco; **Svuota cronologia** la rimuove dalla memoria.

## Gesto a tre dita

La scorciatoia globale resta il metodo supportato. La mappatura di un gesto a tre dita non è inclusa: le soluzioni esaminate usano API private del trackpad e richiedono permessi aggiuntivi, con possibili conflitti con Mission Control e App Exposé.

## Verifiche

`sh scripts/run-smoke-tests.sh` verifica il riconoscimento di testo, URL, immagini e file; il limite della cronologia; i filtri; la persistenza delle preferenze; i formati nativi di trascinamento; e il nome originale nel writer per file URL.

| Controllo | Esito |
| --- | --- |
| Compilazione arm64, bundle e firma ad hoc | Superato |
| Smoke test automatici | Superato |
| Avvio automatico dopo il riavvio del Mac | Confermato manualmente |
| Funzionamento con più monitor | Confermato manualmente |
| Click diagnostico sulla miniatura senza riscrivere gli appunti | Osservati `tileMouseDown`, `itemPointerDown`, `itemPointerUp`, `tileClickNoCopy` |
| Avvio e termine di una sessione `NSDraggingSession` | Osservati `dragStart`, `dragEnd`, `dragSessionEnded`; pannello rimasto visibile durante il drag |
| Registrazione e apertura da scorciatoia globale | Runtime installato: `status=0`, `shortcutTriggered`, `open-complete` |
| Conservazione del nome nel writer file URL | Superato nello smoke test |
| Wrapping visivo di un nome file lungo | Superato con una variante diagnostica temporanea; due righe, estensione visibile |
| Rilascio effettivo del file in Finder e nome originale | Confermato manualmente dall’utente |
| Timeout predefinito e chiusura al clic esterno | Chiusure osservate nei log runtime |
| Modifica live del tema e timeout personalizzato | Non verificati in modo isolato |

Il bundle pubblicato non include l’app compilata: la firma ad hoc è adatta ai test locali, non alla distribuzione senza avvisi su altri Mac. Per distribuire un’app notarizzata serve una firma Developer ID.

I log `[IsolaClipboard]` riportano stati e frame del pannello, senza registrare il contenuto degli appunti. In modalità temporanea `--diagnostic-no-autoclose`, il click diagnostico non modifica la clipboard.

## Identità

- Nome: `Isola Clipboard`.
- Bundle ID: `it.lucazucconi.IsolaClipboard`.
- Versione: `1.0.0` (build `100`).
- Architettura: arm64; deployment target macOS 14.
- Icona app: `IsolaClipboard/Resources/AppIcon.icns`; sorgente vettoriale: `scripts/GenerateAppIcon.swift`.
