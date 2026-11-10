# PEBL per iPad

Port nativo di PEBL (Psychology Experiment Building Language) per iPadOS. Usa lo
stesso interprete C++ e la stessa batteria di test delle versioni desktop, con
un launcher touch al posto di quello desktop.

> **Stato:** il codice è stato scritto senza un Mac a disposizione e **non è
> ancora stato compilato né provato su un iPad**. La prima compilazione (vedi
> sotto) potrebbe richiedere qualche correzione. Prima di raccogliere dati veri,
> prova i test che ti servono sull'iPad che userai.

## 1. Ottenere l'app

Per installare un'app su iPad servono **una compilazione con Xcode** (quindi
macOS) e **una firma Apple**. Ci sono due strade.

### A. Senza Mac (da Windows): GitHub Actions + Sideloadly

1. Crea un account GitHub e fai un *fork* di PEBL (oppure crea un repository tuo)
   con dentro questo codice, incluse le cartelle `ios/` e `.github/workflows/ios.yml`.
2. Carica il codice (push). Nella scheda **Actions** parte il job "iPad build",
   che gira su un Mac virtuale di GitHub (gratuito per i repository pubblici).
   Dura circa 15-30 minuti.
3. Alla fine scarica l'artifact **PEBL-iPad-unsigned** (un file `.ipa` dentro uno zip).
4. Su Windows installa **iTunes** (versione dal sito Apple, non dal Microsoft
   Store) e **Sideloadly** (https://sideloadly.io).
5. Collega l'iPad via USB, apri Sideloadly, trascina il file `.ipa`, inserisci il
   tuo Apple ID e premi *Start*. Sideloadly firma l'app con il tuo account.
6. Sull'iPad (iPadOS 16 o successivo): *Impostazioni → Privacy e sicurezza →
   Modalità sviluppatore* → attivala e riavvia. Poi *Impostazioni → Generali →
   VPN e gestione dispositivi* → autorizza il tuo Apple ID.

Con un Apple ID **gratuito** l'app scade dopo **7 giorni** e va reinstallata (i
dati in Documenti restano). Con l'**Apple Developer Program** (99 €/anno, spesso
lo ha l'università o il laboratorio) la firma dura un anno.

In alternativa a Sideloadly puoi usare AltStore (https://altstore.io), che rinnova
la firma da solo quando iPad e PC sono sulla stessa rete Wi-Fi.

### B. Con un Mac

```bash
brew install cmake
cmake -S ios -B build-ios -G Xcode \
      -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DPEBL_DEVELOPMENT_TEAM=<TEAM_ID>   # da developer.apple.com, anche account gratuito
open build-ios/PEBL.xcodeproj
```

In Xcode scegli lo schema **PEBL**, seleziona l'iPad collegato e premi Run. Se
il bundle id `net.sourceforge.pebl.ipad` è già usato, cambialo con
`-DPEBL_BUNDLE_ID=it.tuonome.pebl`.

## 2. Uso

All'avvio compare il **launcher**:

- in alto: **codice partecipante** (si apre la tastiera; conferma con Invio),
  **lingua** (tocca per cambiarla) e **modalità di risposta** (touch / tastiera);
- al centro: la griglia dei test della batteria (oltre 100), divisa in pagine;
- tocca un test per leggerne la descrizione, scegliere un file di parametri e
  premere **AVVIA**.

Al termine del test l'app torna al launcher e mostra l'esito.

### Gesti durante un test

| Gesto | Effetto | Equivalente desktop |
|---|---|---|
| **4 dita** tenute sullo schermo per 2 secondi | interrompe il test e torna al launcher | Ctrl+Alt+Shift+\ |
| **Tocco con 3 dita** | mostra o nasconde la tastiera a schermo | — |

### Risposte touch

Molti test chiedono tasti, ad esempio la barra spaziatrice o i due Shift. Con
**Risposte: touch** (l'impostazione predefinita), i test basati sul sistema
`Layout` di PEBL (circa 50, tra cui flanker, Stroop, go/no-go, Simon, ANT,
Corsi...) usano invece:

- un tocco **ovunque sullo schermo** quando la risposta è una sola (es. go/no-go);
- **due pulsanti a schermo** quando le risposte sono due (es. sinistra/destra).

I test con più di due risposte da tastiera (frecce, numeri) e i test più vecchi
che leggono direttamente i tasti richiedono una **tastiera Bluetooth o Smart
Keyboard**: in quel caso scegli **Risposte: tastiera**. Per scrivere testo basta
la tastiera a schermo.

### Dove sono i dati

Apri l'app **File** → *Sul mio iPad* → **PEBL**:

```
PEBL/
├── battery/<test>/data/      ← dati di ogni test (CSV ecc.)
├── battery/<test>/params/    ← file di parametri (.par.json)
├── my-experiments/<nome>/<nome>.pbl   ← i tuoi script PEBL
└── logs/pebl-log.txt         ← registro dell'ultima sessione (utile in caso di errori)
```

Da lì puoi condividere i file (AirDrop, e-mail, Drive...) oppure copiarli su un
computer: Finder su Mac, iTunes / app Dispositivi Apple su Windows, sezione
"Condivisione file".

Gli aggiornamenti dell'app aggiornano gli script della batteria ma **non
toccano mai** le cartelle `data/` né i tuoi file `.par.json`.

### Consigli per le sessioni sperimentali

- Attiva **Accesso guidato** (*Impostazioni → Accessibilità → Accesso guidato*):
  blocca il partecipante dentro l'app e disattiva i gesti di sistema (Home,
  Centro di Controllo, multitasking a 4/5 dita).
- **Modalità aereo** e **Non disturbare** per evitare notifiche.
- Se l'app va in background durante un test (chiamata, notifica toccata...), i
  tempi di quel test non sono affidabili. Nel log compare un avviso
  `app entering background`.

## 3. Differenze rispetto a PEBL desktop

| Funzione | Su iPad |
|---|---|
| Interprete, grafica, testo, immagini, suoni, registrazione vocale | come su desktop |
| Rete (`ConnectToHost`...) e HTTP (`PostHTTP`, upload dei dati) | sì (HTTP tramite NSURLSession invece di libcurl) |
| `SystemCall`, `SystemCallUpdate` | non disponibili (iOS non permette di lanciare programmi): restituiscono errore |
| `LaunchFile` | gli URL web si aprono in Safari, i file locali nell'app File |
| Porta parallela/seriale, Lab Streaming Layer, eye tracker | non disponibili |
| Finestra | sempre a schermo intero; uno script pensato per 800×600 viene ingrandito mantenendo le proporzioni (bande nere ai lati) |
| `GetSystemType()` | restituisce `"IOS"` |
| Tempi di reazione | stessa risoluzione al millisecondo del desktop, ma la latenza del touchscreen è diversa da quella di tastiera e mouse: non confrontare direttamente i TR raccolti su dispositivi diversi |

## 4. Note tecniche (per chi modifica il codice)

- Piattaforma: macro `PEBL_IOS` (insieme a `PEBL_UNIX`). Tutte le modifiche al
  codice comune sono dentro `#ifdef PEBL_IOS`; le altre piattaforme non cambiano.
- Interprete **iterativo** (`PEBL_ITERATIVE_EVAL`, lo stesso della versione Web):
  lo stack del thread principale di iOS è piccolo (1 MB) e l'interprete
  ricorsivo rischierebbe di esaurirlo.
- iOS non permette all'app di terminare né di avviare processi, quindi launcher
  e test girano **nello stesso processo** (`src/platforms/ios/PEBLiOSRunLoop.cpp`).
  Errori fatali, `ExitQuietly()` e il gesto a 4 dita lanciano l'eccezione
  `PEBLScriptExit`, che riporta al launcher invece di chiamare `exit()`.
- File nuovi: `src/platforms/ios/` (glue Objective-C++, run loop),
  `src/utility/PEBLHTTP_ios.mm` (HTTP), `ios/` (CMake, Info.plist, icona,
  launcher `ios/resources/ios-launcher.pbl`), `.github/workflows/ios.yml`.
- File modificati: `PEBL.cpp`, `PError.*`, `PEBLPath.*`, `PEBLUtility.cpp`,
  `PEBLEnvironment.cpp`, `PEBLHTTP.h`, `grammar.y` / `grammar.tab.cpp`,
  `PEventLoop-es.cpp`, `PlatformWindow.cpp`, `PlatformEventQueue.cpp`,
  `PlatformTextBox.cpp`, `PlatformTimer.cpp` (corretto un dereference di un
  puntatore NULL in `GetTimeOfDay`), `pebl-lib/Layout.pbl`.
- Librerie: SDL2 2.30, SDL2_image, SDL2_ttf (con FreeType/HarfBuzz),
  SDL2_mixer, SDL2_net, scaricate da CMake e linkate staticamente; SDL2_gfx è
  quella inclusa in `libs/`.
