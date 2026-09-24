# Architettura

PeopleCare Remote Camera trasforma un telefono Android in una camera remota per la
regia. Il sistema ha **due piani separati**:

- **piano video**: il telefono trasmette a **Cloudflare Stream** (SRT, fallback RTMPS);
  OBS riceve da Cloudflare in **SRT playback**; la Control Room mostra un'anteprima
  HLS/LL-HLS con lo Stream Player. Il video **non passa mai** dal Worker.
- **piano di controllo**: telefono e Control Room si collegano con WebSocket cifrati
  (WSS) a un **Cloudflare Worker** con un **Durable Object**, che instrada comandi, ACK,
  stato e telemetria. Nessuna rete locale, IP pubblico, port forwarding o VPN.

```
┌──────────────────────── Telefono Android · PeopleCare Remote Camera ───────────────────────┐
│  Flutter (Dart): UI, AppController, ControlClient, CommandExecutor, pairing, diagnostica   │
│        ⇅ MethodChannel "…/engine" + EventChannel "…/events" (un solo motore)                │
│  Kotlin: CameraEngine su RootEncoder 2.8.1 → Camera2 → OpenGL → MediaCodec H.264 + AAC     │
│          StreamingService (foreground camera|microphone), wake lock, Wi-Fi lock            │
└───────────┬──────────────────────────────────────────────────────────┬─────────────────────┘
            │ SRT caller (primario) / RTMPS (fallback)                  │ WSS /ws/device
            │ credenziali di ingest ricevute dal Worker                 │ Authorization: Bearer <token>
            ▼                                                          ▼
┌──────────────────────────────┐                     ┌────────────────────────────────────────┐
│ Cloudflare Stream            │◄── Stream API ──────│ Cloudflare Worker + Durable Object      │
│ Live Input (1 per camera)    │   (solo server,     │ "studio" (SQLite): camere, token (hash),│
│  • SRT/RTMPS playback        │    secret Wrangler) │ pairing, sessioni, comandi, eventi      │
│  • HLS / LL-HLS + Player     │── webhook Live ────►│ polling stato + watchdog, rate limit    │
└──────┬─────────────┬─────────┘   (opzionale)       └───────────────────┬────────────────────┘
       │ SRT playback │ HLS (iframe Player)                               │ WSS /ws/control (cookie)
       ▼              ▼                                                   ▼
┌──────────────┐  ┌──────────────────────────────────────────────────────────────────────────┐
│ OBS Studio   │  │ Control Room (Chrome su Ubuntu): dashboard CAM 01–04+, dettaglio camera, │
│ (Ubuntu)     │  │ comandi remoti con ACK, telemetria, log, pairing, URL SRT per OBS        │
│ Media Source │  └──────────────────────────────────────────────────────────────────────────┘
└──────────────┘
```

## Componenti

| Cartella | Componente | Tecnologia |
| --- | --- | --- |
| `apps/remote_camera` | App Android "PeopleCare Remote Camera" (`tv.peoplecare.remotecamera`) | Flutter 3.47 / Dart 3.13 + Kotlin, RootEncoder 2.8.1, minSdk 26, targetSdk 36 |
| `apps/control_room` | Pannello di regia web | Preact 10 + Vite 7 + TypeScript 5.9, jsQR per la scansione QR |
| `cloudflare/worker` | Control plane + hosting della Control Room | Workers + Durable Object SQLite con WebSocket Hibernation, Rate Limiting binding, static assets |
| `docs/protocol-fixtures` | Messaggi "golden" del protocollo | JSON usati dai test di Worker, Control Room e app |
| `tools/android-compile-check` | Verifica dei sorgenti Kotlin senza Android SDK | Gradle + Robolectric android-all |

### Worker e Durable Object

- `src/index.ts` — ingresso HTTP: `/api/health`, rate limit all'edge sugli endpoint pubblici
  (`/api/auth/login`, `/api/pair/*`, `/api/webhooks/stream`), inoltro di `/api/*` e `/ws/*` al
  Durable Object, file statici della Control Room per tutto il resto.
- `src/studio.ts` — un unico Durable Object `studio` (una regia per deployment, fino a 16 slot
  camera) che possiede tutto lo stato in SQLite:
  - `cameras` (slot, nome, **hash** SHA-256 del token dispositivo, live input, capabilities,
    stato, telemetria, stato Cloudflare), `pairings` (hash del codice e del token di polling),
    `sessions` (hash dei token di sessione), `commands` (registro di ogni comando e del suo esito),
    `events` (log di regia, ultimi 1000), `rate_limits`, `meta`.
  - WebSocket con **Hibernation API**: i socket restano aperti anche quando l'oggetto è
    ibernato; lo stato del socket è in `serializeAttachment`.
  - `alarm()`: timeout dei comandi, heartbeat dei telefoni (chiusura 4008 dopo 50 s di silenzio),
    scadenza sessioni, **polling dello stato del live input** (ogni `CF_POLL_INTERVAL_SECONDS`
    mentre una camera è attiva), watchdog, manutenzione.
- `src/cloudflare/stream.ts` — client minimo della **Stream Live Input API**
  (create/get/update/enable/disable/rotate_keys/delete/videos); il token API compare solo
  nell'header `Authorization` e non viene mai registrato nei log.
- `src/shared/protocol.ts` — protocollo v1 condiviso (usato anche dalla Control Room):
  comandi, validazione, sanitizzazione di stato/telemetria/capabilities.

### App Android

Livello Dart (`lib/src`):

- `app/app_controller.dart` — stato dell'app, orchestrazione di motore, regia e pairing,
  invio di `hello`/`state`/`telemetry`, esecuzione dei comandi (`command_executor.dart`).
- `control/control_client.dart` — WebSocket verso `/ws/device` con token nell'header,
  backoff esponenziale con jitter (1 s → 30 s), heartbeat applicativo (ping ogni 15 s,
  riconnessione dopo 45 s senza messaggi), riconnessione immediata al cambio di rete,
  distinzione tra token revocato (HTTP 401) e problemi di rete.
- `protocol/` — parsing/validazione dei comandi identici al server (fixture condivise),
  `CommandGuard` anti-replay.
- `pairing/` — richiesta del codice, polling, salvataggio in `flutter_secure_storage`
  (Android Keystore).
- `engine/engine_bridge.dart` — unico ponte verso il motore nativo (MethodChannel +
  EventChannel), nessun FFmpegKit.
- `logging/` — log INFO/WARNING/ERROR con redazione automatica di token, passphrase e
  chiavi; report diagnostico.
- `ui/` — Material 3 scuro: associazione, schermata camera (anteprima, LIVE/RECONNECTING/
  OFFLINE/ERROR, spie CAMERA/CLOUDFLARE/REGIA), impostazioni, diagnostica.

Livello nativo Kotlin (`android/app/src/main/kotlin/tv/peoplecare/remotecamera`):

- `RemoteCameraApplication` + `EngineHolder` — il `FlutterEngine` e il `CameraEngine`
  vivono nell'`Application`: sopravvivono alla chiusura dell'Activity mentre il servizio
  in foreground continua a trasmettere.
- `CameraEngine` — **un solo motore** RootEncoder `GenericStream` per camera, anteprima,
  codifica e streaming: `Camera2Source` + `MicrophoneSource`, H.264 (profilo scelto da
  RootEncoder) e AAC via MediaCodec, GOP 2 s, SRT/RTMPS, registrazione MP4 di backup,
  adattamento del bitrate (`QueueAwareBitrateAdapter`), zoom/torcia/fuoco/esposizione.
- `StreamingService` — servizio in foreground `camera|microphone` con notifica persistente
  (azione "STOP DIRETTA"), `PARTIAL_WAKE_LOCK` e Wi-Fi lock a bassa latenza durante la diretta.
- `CapabilityProbe` — interroga Camera2 e MediaCodec: camere, zoom, torcia, autofocus,
  punto di fuoco, esposizione, FPS per risoluzione, bitrate massimo dell'encoder.
- `NetworkMonitor`, `DeviceMonitor` — rete (tipo, a consumo, banda stimata), batteria,
  temperatura, stato termico, spazio libero.
- `CameraBridgePlugin` — MethodChannel/EventChannel, anteprima tramite **SurfaceProducer**
  (texture Flutter, niente PlatformView/WebView).

### Control Room

Single page app servita dal Worker (stessa origine: niente CORS, cookie `SameSite=Strict`).
`store.ts` è un reducer puro alimentato dal WebSocket `/ws/control` (snapshot iniziale +
aggiornamenti), `controls.ts` decide quali controlli sono abilitati in base alle
capabilities e allo stato reale, `commands.ts` genera `commandId` casuali e `issuedAt`
corretti con l'offset dell'orologio del server.

## Flusso video

1. Dopo l'associazione il Worker crea (o ritrova) il **live input** della camera tramite la
   Stream API, con `recording.mode = automatic` (necessario per l'anteprima HLS/Player),
   `deleteRecordingAfterDays` e, se abilitato, `preferLowLatency` (LL-HLS, beta).
2. Il telefono chiede la configurazione (`config_request`) e riceve **solo** le credenziali
   di ingest della propria camera (`CameraStreamingConfig`): SRT come primario, RTMPS come
   fallback, più i parametri video. Le credenziali di **playback** non arrivano mai al telefono.
3. `start_stream` (dal telefono o dalla regia) avvia la trasmissione SRT in modalità caller
   (l'unica supportata da Stream) verso `srt://…:778` con `streamid` e `passphrase`.
4. OBS legge l'URL **SRT playback** del live input (mostrato in Control Room solo su richiesta
   esplicita dell'operatore, con evento di audit). La Control Room mostra lo **Stream Player**
   (HLS/LL-HLS) come anteprima: ha alcuni secondi di ritardo; il riferimento a bassa latenza
   è OBS.

### Perché SRT e non WHIP/WHEP

Secondo la documentazione di Cloudflare Stream, WHIP (ingest WebRTC) e WHEP (playback
WebRTC) vanno usati **insieme**: un live input WebRTC non è riproducibile in SRT/RTMPS né in
HLS. Con WHIP, OBS non potrebbe ricevere il flusso in SRT e la Control Room perderebbe il
player HLS. Per questo l'ingest è SRT (fallback RTMPS) e WHEP non viene usato. Cloudflare
documenta per SRT/RTMPS playback una latenza "glass-to-glass" inferiore a 1 secondo nelle
app native (ffmpeg): è il percorso usato da OBS.

## Stati

Stato dello stream sul telefono (`streamStatus`): `idle` → `connecting` → `live` ⇄
`reconnecting` → `stopping` → `idle`; `error` per errori non recuperabili (permessi,
configurazione mancante, live input disabilitato). La UI mostra **LIVE** in rosso solo
quando RootEncoder ha confermato la connessione (`onConnectionSuccess`); con la **PAUSA**
la sessione SRT resta aperta e si inviano video nero e audio muto.

Stato dell'ingest visto da Cloudflare (`cloudflare.state`): `live`, `reconnecting`,
`offline`, `disabled`, `error`, `unknown`, `unconfigured`, ricavato dal campo `status` del
live input (polling) o dai webhook `live_input.connected/disconnected/errored`.

Collegamento alla regia (`LinkState`): `connecting`, `connected`, `reconnecting`,
`disconnected`, `error` (token revocato).

## Affidabilità

| Meccanismo | Dove | Dettaglio |
| --- | --- | --- |
| Riconnessione SRT/RTMPS con backoff | `CameraEngine` | 1 s ×2 fino a 30 s, jitter 50%, tentativi illimitati durante la diretta |
| Fallback RTMPS | `CameraEngine` | dopo 3 fallimenti SRT consecutivi senza mai essersi connesso (es. UDP bloccato), se abilitato |
| Cambio di rete | `NetworkMonitor` → `CameraEngine`, `ControlClient` | riavvio immediato dello stream e del WebSocket sulla nuova rete |
| Stallo | supervisore del motore | 8 s a zero byte inviati mentre LIVE → riavvio completo; 45 s in `connecting` → riavvio |
| Watchdog lato server | Durable Object | se Cloudflare vede il live input scollegato per 2 poll mentre il telefono è LIVE da ≥30 s, invia `reconnect` (vero comando con ACK, pausa di 120 s) |
| Heartbeat regia | `ControlClient` + DO | ping ogni 15 s; il telefono si riconnette dopo 45 s di silenzio, il server chiude dopo 50 s (4008) |
| Stato non perso | app | lo stato completo viene ripubblicato a ogni riconnessione (`hello` + `state`); i comandi non vengono mai accodati |
| Background | `StreamingService` | servizio in foreground, wake lock parziale, Wi-Fi lock, la diretta continua a schermo spento |

## Protocollo di controllo

Versione 1, JSON su WebSocket, dettagli in [PROTOCOL.md](PROTOCOL.md). Ogni comando ha un
`commandId` univoco (16–64 caratteri) generato dalla Control Room, un `issuedAt`, e riceve
ACK reali dal telefono: `received` subito dopo la validazione, `completed` con `ok`,
`result` o `error` al termine. Il server non simula mai un ACK: se il telefono è offline
il comando fallisce subito (`camera_offline`), se l'ACK non arriva entro 25 s va in `timeout`.

## Sicurezza

- **Segreti solo lato server**: `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`,
  `CONTROL_ROOM_PASSWORD`, `STREAM_WEBHOOK_SECRET` sono secret di Wrangler. L'APK e la
  Control Room non contengono credenziali Cloudflare.
- **Principio del minimo privilegio**: il telefono riceve solo le credenziali di ingest della
  propria camera; la Control Room riceve le credenziali di playback SRT solo quando
  l'operatore le chiede (evento registrato nel log).
- **Token dispositivo**: 256 bit casuali, emesso al termine del pairing (finché il telefono non
  si collega, ogni poll ne emette uno nuovo e resta valido solo l'ultimo), salvato con
  `flutter_secure_storage` (Android Keystore), sul server solo come hash SHA-256; revocabile
  dalla regia (chiusura 4001 + rotazione/disabilitazione/cancellazione del live input secondo
  `REVOKE_ACTION`).
- **Pairing**: codice monouso di 8 caratteri (alfabeto Crockford base32, 40 bit), scadenza
  10 minuti, limite di tentativi per IP e per sessione; codici e token salvati solo come hash,
  confronti dei segreti a tempo costante. Vedi [PAIRING.md](PAIRING.md).
- **Control Room**: password (≥12 caratteri) → cookie di sessione `HttpOnly`, `Secure`,
  `SameSite=Strict`, controllo dell'header `Origin` su login, mutazioni e WebSocket.
- **Anti-replay**: `commandId` registrato prima dell'invio e mai accettato due volte dal
  server; sul telefono `CommandGuard` rifiuta id già visti, `seq` non crescenti e comandi
  scaduti (`expiresAt`, orologio del server stimato con ping/pong); `issuedAt` deve essere
  entro ±120 s dall'orologio del server.
- **Validazione e limiti**: ogni messaggio è validato (tipo, valori, dimensione ≤ 32 KB);
  token bucket per connessione; rate limit per IP su login e pairing (SQLite + binding
  Rate Limiting all'edge).
- **Trasporto**: solo HTTPS/WSS verso la regia (`usesCleartextTraffic=false`), SRT con
  passphrase AES di Cloudflare, RTMPS su TLS.
- **Diagnostica**: il report copiato dall'app non contiene token, password, passphrase,
  streamid o chiavi (redazione testata).
