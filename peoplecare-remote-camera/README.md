# PeopleCare Remote Camera

Trasforma un telefono Android in una **camera remota professionale** per la regia
PeopleCareTV:

```
APP ANDROID ──SRT (fallback RTMPS)──► CLOUDFLARE STREAM LIVE INPUT ──SRT PLAYBACK──► OBS STUDIO (Ubuntu)
                                                 └──HLS / LL-HLS──► anteprima nella CONTROL ROOM

CONTROL ROOM (PC, Chrome) ──WSS──► CLOUDFLARE WORKER + DURABLE OBJECT ◄──WSS── APP ANDROID
```

- **Nessuna rete locale**, IP pubblico, port forwarding, Tailscale o VPN: telefono e regia
  si parlano solo tramite Cloudflare.
- **Un solo motore** sul telefono (RootEncoder 2.8.1, nativo Kotlin) per camera, anteprima,
  codifica H.264/AAC con MediaCodec e trasmissione SRT/RTMPS; Flutter per l'interfaccia.
- **Comandi remoti con ACK reali** (ricevuto/completato/errore), controlli abilitati solo se
  l'hardware li supporta, telemetria in tempo reale.
- **Segreti solo lato server**: account ID e token API di Cloudflare sono secret di Wrangler;
  l'APK e il browser non li vedono mai.

## Struttura

```
peoplecare-remote-camera/
├── apps/
│   ├── remote_camera/          App Android Flutter + Kotlin (tv.peoplecare.remotecamera)
│   │   ├── lib/src/            UI, stato, protocollo, pairing, controllo, diagnostica (Dart)
│   │   ├── android/app/src/main/kotlin/tv/peoplecare/remotecamera/   motore nativo RootEncoder
│   │   ├── test/               60 test Dart
│   │   └── test_e2e/           telefono per la verifica end-to-end locale
│   └── control_room/           Control Room web (Preact + Vite + TypeScript)
├── cloudflare/worker/          Worker + Durable Object: control plane, API Stream, hosting Control Room
├── docs/                       ARCHITECTURE, CLOUDFLARE_SETUP, OBS_SETUP, ANDROID_SETUP,
│                               PAIRING, PROTOCOL, TEST_PLAN, protocol-fixtures/
├── scripts/                    setup, build, deploy, test, verifiche
├── tools/
│   ├── android-compile-check/  verifica dei sorgenti Kotlin senza Android SDK
│   └── e2e/                    verifica end-to-end locale (wrangler dev + Chromium + telefono Dart)
├── .env.example                tutte le variabili, con placeholder
└── README.md
```

## Avvio rapido

1. **Prerequisiti**: Node.js ≥ 22, Flutter stable 3.47 con Android SDK 36 e JDK 17,
   account Cloudflare con Stream attivo.
2. **Dipendenze**: `scripts/setup.sh`
3. **Cloudflare** ([guida](docs/CLOUDFLARE_SETUP.md)):
   ```bash
   cd cloudflare/worker && npx wrangler login && cd ../..
   scripts/deploy_cloudflare.sh
   cd cloudflare/worker
   npx wrangler secret put CLOUDFLARE_ACCOUNT_ID    # placeholder: CLOUDFLARE_ACCOUNT_ID
   npx wrangler secret put CLOUDFLARE_API_TOKEN     # placeholder: CLOUDFLARE_API_TOKEN (permesso Stream Edit)
   npx wrangler secret put CONTROL_ROOM_PASSWORD    # almeno 12 caratteri
   ```
   Controllo: `https://<worker>.<sottodominio>.workers.dev/api/health` → `"streamConfigured":true`.
4. **APK** ([guida](docs/ANDROID_SETUP.md)):
   ```bash
   CONTROL_PLANE_URL=https://<worker>.<sottodominio>.workers.dev scripts/build_android.sh
   adb install -r dist/peoplecare-remote-camera-debug.apk
   ```
   (equivalente: `cd apps/remote_camera && flutter pub get && cd android && ./gradlew assembleDebug`)
5. **Associazione** ([guida](docs/PAIRING.md)): sul telefono **ASSOCIA ALLA REGIA** →
   codice/QR → nella Control Room **Aggiungi camera** → nome `CAM 01 - SALA`.
6. **OBS** ([guida](docs/OBS_SETUP.md)): Control Room → camera → **Mostra URL SRT per OBS**
   → Sorgente multimediale con *File locale* disattivato e *Input* = URL copiato.

## Funzionalità

| Area | Cosa fa |
| --- | --- |
| Streaming | SRT caller verso Cloudflare (primario), RTMPS automatico se SRT non si connette dopo 3 tentativi; H.264 + AAC, GOP 2 s; stati connecting/connected/reconnecting/disconnected/error; LIVE rosso solo a connessione confermata |
| Affidabilità | backoff esponenziale con jitter, riavvio immediato al cambio rete, rilevamento stallo (8 s senza dati), watchdog lato server su Cloudflare, heartbeat del controllo, servizio in foreground con wake lock e Wi-Fi lock, configurazione in cache |
| Controlli | START/STOP/PAUSE/RESUME (pausa con sessione SRT mantenuta), RESTART, RECONNECT, VIDEO e AUDIO ON/OFF separati, camera frontale/posteriore, zoom, torcia, autofocus, punto di fuoco, esposizione, risoluzione, FPS, bitrate AUTO/MANUALE, preset LOW/STANDARD/HIGH, RECORD BACKUP ON/OFF |
| Telemetria | rete e uplink stimato, bitrate e coda, FPS, risoluzione, batteria e temperatura, stato termico, lente, zoom, torcia, microfono, uptime, riconnessioni, errori recenti, spazio libero |
| Control Room | dashboard CAM 01–04 (e oltre, fino a 16), dettaglio camera con anteprima Stream Player (HLS/LL-HLS), comandi con stato ACK, log, pairing con codice o QR via webcam, URL SRT per OBS, gestione del live input |
| Sicurezza | HTTPS/WSS, token dispositivo per camera (hash sul server, Keystore sul telefono), password e sessione della regia, pairing monouso con scadenza, anti-replay, validazione, rate limit, revoca, report diagnostico senza segreti |

## Stato della verifica

Verificato **in questo ambiente** (Linux, Node 22.22.2, Flutter 3.47.5 / Dart 3.13.4, JDK 21):

| Verifica | Risultato |
| --- | --- |
| Worker: `tsc` (sorgenti e test) | nessun errore |
| Worker: `npm test` (Vitest 4.1 nel runtime `workerd`, Durable Object e WebSocket reali) | **60/60** test superati |
| Worker: `wrangler deploy --dry-run` | bundle 89 KiB (22 KiB gzip), binding STUDIO, RL_PUBLIC, ASSETS |
| Control Room: `tsc`, `vitest`, `vite build` | nessun errore, **21/21** test, bundle 63,7 KB + jsQR 130,8 KB caricato solo per la scansione |
| App: `flutter analyze` | nessun problema |
| App: `flutter test` | **60/60** test superati |
| App: sorgenti Kotlin (`scripts/check_android_sources.sh`) | app + RootEncoder 2.8.1 compilano (Kotlin 2.4.0) contro android-all API 36 e flutter.jar; 279 riferimenti a `android.*`, tutti API pubbliche dell'SDK di Android 16; 5 API successive a minSdk 26, tutte protette da controllo di versione. La verifica ha trovato e fatto correggere un errore reale (firma di `startRecord`) |
| End-to-end locale (`tools/e2e/run_e2e.sh`) | Worker in `wrangler dev` + Control Room in Chromium + livello Dart reale del telefono: login, pairing con codice, camera online, START con ACK reale e LIVE, zoom, torcia (disabilitata sulla frontale), cambio camera, PAUSE/RESUME, stato Cloudflare dal polling, URL SRT per OBS, STOP, disconnessione. API Stream **simulata** e motore camera **simulato** (dichiarati in `tools/e2e/README.md`) |
| Script `setup.sh`, `build_control_room.sh`, `test_all.sh --native`, `check_android_sources.sh` | eseguiti con successo |
| **APK di debug** (CI GitHub, `.github/workflows/peoplecare-remote-camera.yml`) | `scripts/build_android.sh debug` su ubuntu-24.04 con JDK 17, Android SDK del runner e RootEncoder 2.8.1 da JitPack: `flutter analyze` e `flutter test` superati, `Running Gradle task 'assembleDebug'` → `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (160 MB). Nella CI passano anche i job Worker/Control Room ed end-to-end |

**Non verificato qui** (e perché):

| Voce | Motivo | Come verificarla |
| --- | --- | --- |
| APK compilato *in questo ambiente* | la policy di rete blocca `dl.google.com` (Android SDK e Google Maven) e `jitpack.io` (RootEncoder); la build è stata quindi eseguita e verificata nella CI GitHub (riga sopra) | scaricare l'artifact `peoplecare-remote-camera-debug-apk` dal run del workflow, oppure `scripts/build_android.sh` su un PC |
| Esecuzione su telefono reale (camera, encoder, SRT, servizio in foreground, termica) | nessun dispositivo | [TEST_PLAN.md](docs/TEST_PLAN.md) §2 |
| Chiamate reali all'API Cloudflare Stream, webhook, player | nessuna credenziale (non vanno mai nel repository) | endpoint e campi seguono la documentazione ufficiale di Cloudflare Stream e i tipi dell'SDK ufficiale; collaudo con [CLOUDFLARE_SETUP.md](docs/CLOUDFLARE_SETUP.md) |
| OBS che riceve l'SRT playback reale | nessun flusso reale | [OBS_SETUP.md](docs/OBS_SETUP.md); campi e opzioni verificati sul codice sorgente di OBS e FFmpeg |
| `scripts/build_rootencoder_from_source.sh`, workflow GitHub Actions | richiedono Google Maven / un push riuscito | eseguirli fuori da questo ambiente |

## Funzioni non disponibili su tutti i dispositivi

L'app interroga Camera2 e MediaCodec e **disattiva** ciò che l'hardware non supporta (anche
in Control Room); i comandi forzati vengono rifiutati con errore esplicito, mai simulati:

- **Torcia**: solo sulla lente con flash (tipicamente non sulla frontale).
- **50/60 fps**: solo se la camera dichiara il range e l'encoder H.264 regge risoluzione×FPS.
- **1080p**: solo se camera ed encoder lo supportano (altrimenti 720p).
- **Zoom ratio**: Android 11+ su camere non LEGACY; altrimenti zoom digitale.
- **Punto di fuoco / autofocus**: solo con regioni AF / modalità AF continue disponibili.
- **Esposizione**: solo con range di compensazione non nullo.
- **Registrazione backup**: richiede almeno 1 GB libero; su Android 8–9 il file resta nella
  cartella dell'app.
- **Non supportati per scelta**: HEVC e 4K (Cloudflare Stream Live accetta H.264 + AAC),
  WHIP/WHEP (renderebbero impossibile l'SRT playback per OBS e l'HLS: vedi
  [ARCHITECTURE.md](docs/ARCHITECTURE.md)), avvio della camera da background su Android 11+
  (limite del sistema: la camera si arma aprendo l'app, poi funziona a schermo spento).

## Documentazione

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — componenti, flussi, stati, affidabilità, sicurezza
- [CLOUDFLARE_SETUP.md](docs/CLOUDFLARE_SETUP.md) — token, secret, deploy, webhook, sviluppo locale
- [OBS_SETUP.md](docs/OBS_SETUP.md) — Sorgente multimediale SRT su Ubuntu, parametri verificati
- [ANDROID_SETUP.md](docs/ANDROID_SETUP.md) — toolchain, APK, installazione, uso, limiti
- [PAIRING.md](docs/PAIRING.md) — associazione, revoca, sicurezza del pairing
- [PROTOCOL.md](docs/PROTOCOL.md) — protocollo v1, comandi, ACK, API HTTP
- [TEST_PLAN.md](docs/TEST_PLAN.md) — test automatici e collaudo manuale

## Licenze di terze parti

RootEncoder (Apache-2.0), Flutter e pacchetti Dart (BSD/MIT), Preact (MIT), jsQR
(Apache-2.0), Vite/Vitest (MIT), Wrangler (MIT/Apache-2.0).
