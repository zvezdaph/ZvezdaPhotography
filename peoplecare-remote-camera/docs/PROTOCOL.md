# Protocollo di controllo v1

JSON su WebSocket (frame di testo, massimo 32 KB). Ogni messaggio ha `"v": 1` e `"type"`.
Implementazioni: `cloudflare/worker/src/shared/protocol.ts` (Worker e Control Room) e
`apps/remote_camera/lib/src/protocol/protocol.dart` (telefono). I messaggi di esempio in
`docs/protocol-fixtures/` sono verificati dai test di **tutti e tre** i componenti.

## Connessioni

| Endpoint | Chi | Autenticazione |
| --- | --- | --- |
| `wss://<worker>/ws/device` | telefono | header `Authorization: Bearer <device token>` (mai nell'URL) |
| `wss://<worker>/ws/control` | Control Room | cookie di sessione `pcrc_session` + header `Origin` consentito |

Una `GET /ws/device` senza upgrade risponde **401** se il token è revocato e **426** se è
valido: il telefono la usa per distinguere una revoca da un problema di rete.

Codici di chiusura:

| Codice | Significato | Comportamento del client |
| --- | --- | --- |
| 4001 | dispositivo revocato | il telefono dimentica la regia e torna alla schermata di associazione |
| 4002 | sostituito da una nuova connessione con lo stesso token | riconnessione con backoff |
| 4003 | sessione di regia scaduta o logout | la Control Room torna al login |
| 4008 | nessun messaggio dal telefono per 50 s | riconnessione con backoff |
| 1008 | troppi messaggi (rate limit) | riconnessione con backoff |

## Telefono → server

| `type` | Contenuto | Quando |
| --- | --- | --- |
| `hello` | `device` (modello, versione app, versione Android), `capabilities`, `state` | dopo ogni `welcome` |
| `state` | `state` (+ `capabilities` se cambiate) | a ogni cambio di stato (debounce 150 ms) |
| `telemetry` | `telemetry` | ogni 2 s in diretta, ogni 10 s altrimenti |
| `ack` | `commandId`, `stage` (`received`/`completed`), `ok`, `result`, `error`, `ts` | per ogni comando |
| `config_request` | — | dopo ogni `welcome`, prima di `start_stream` se la configurazione manca, da "RICARICA CONFIGURAZIONE" |
| `log` | `level`, `message` (≤300 caratteri) | eventi rilevanti (max 60/min registrati) |
| `ping` | `t` (orologio locale) | ogni 15 s |

## Server → telefono

| `type` | Contenuto |
| --- | --- |
| `welcome` | `cameraId`, `cameraName`, `slot`, `connId`, `serverTime`, `heartbeatIntervalMs`, `cloudflare` (`configured`, `state`) |
| `config` | `config`: `CameraStreamingConfig` **oppure** `error` (`cloudflare_not_configured`, `live_input_disabled`, …); inviato anche spontaneamente dopo la rotazione delle chiavi |
| `command` | comando da eseguire (vedi sotto) |
| `cloudflare_status` | `state`, `status` (valore grezzo di Cloudflare), `error`, `at` |
| `camera_info` | `cameraName`, `slot` (dopo una modifica dalla regia) |
| `revoked` | seguito dalla chiusura 4001 |
| `pong` | `t` (eco), `serverTime` (per stimare l'offset dell'orologio) |
| `error` | `code`, `message` (messaggio non valido, rate limit, …) |

`CameraStreamingConfig` (solo al telefono, mai alla Control Room; il telefono la conserva nello
storage cifrato e può quindi andare in onda anche se la regia è momentaneamente irraggiungibile):

```json
{
  "cameraId": "cam_…", "cameraName": "CAM 01 - SALA",
  "protocol": "srt", "url": "srt://…:778", "host": "…", "port": 778,
  "streamId": "…", "passphrase": "…",
  "fallback": { "protocol": "rtmps", "url": "rtmps://…:443/live/", "host": "…", "port": 443, "streamKey": "…" },
  "resolution": "1080p", "fps": 30, "videoBitrateKbps": 5000, "audioBitrateKbps": 128,
  "bitrateMode": "auto", "keyframeIntervalSec": 2, "srtLatencyMs": 500, "issuedAt": 1790000000000
}
```

## Control Room → server

| `type` | Contenuto |
| --- | --- |
| `command` | `commandId` (16–64 caratteri `[A-Za-z0-9_-]`, generato dal browser), `cameraId`, `command`, `value`, `issuedAt` (ms, orologio del server stimato) |
| `ping` | `t` |

## Server → Control Room

| `type` | Contenuto |
| --- | --- |
| `snapshot` | stato completo all'apertura: `config`, `cameras`, ultimi 100 `events`, `commands` degli ultimi 10 minuti, `operator`, `serverTime` |
| `camera_update` | `camera` (vista completa: online, capabilities, stato, telemetria, stato Cloudflare, URL del player) |
| `camera_removed` | `cameraId` |
| `telemetry` | `cameraId`, `telemetry` |
| `command_status` | `commandId`, `cameraId`, `command`, `value`, `status`, `result`, `error`, `issuedBy`, `updatedAt` |
| `event` | `event` del log di regia (`ts`, `level`, `source`, `message`, `cameraId`) |
| `pong`, `error` | come sopra |

## Comandi

| `command` | `value` | Note |
| --- | --- | --- |
| `start_stream` | — | avvia SRT (fallback RTMPS) con la configurazione del server |
| `stop_stream` | — | |
| `pause` | — | video nero + audio muto, **sessione SRT mantenuta** |
| `resume` | — | richiede un keyframe |
| `restart_stream` | — | stop + start completo |
| `reconnect` | — | chiude e riapre la connessione di trasmissione |
| `switch_camera` | `"front"` \| `"back"` | |
| `set_zoom` | numero 0.1–100 (arrotondato a 0.01) | limitato al range reale della lente |
| `zoom_in`, `zoom_out` | passo opzionale (0, 5], default 0.5 | |
| `set_audio_enabled`, `set_video_enabled` | booleano | |
| `set_torch` | booleano | solo se la lente ha il flash |
| `set_autofocus` | booleano | continuo ON / fuoco bloccato |
| `focus_point` | `{ "x": 0–1, "y": 0–1 }` | coordinate nel fotogramma trasmesso |
| `set_exposure` | intero −100…100 | indice di compensazione, limitato al range della camera |
| `set_resolution` | `"720p"` \| `"1080p"` | riavvia l'encoder (breve interruzione) |
| `set_fps` | 25 \| 30 \| 50 \| 60 | solo se supportato alla risoluzione corrente |
| `set_bitrate` | `{ "mode": "auto" \| "manual", "kbps": 500–12000 }` | al volo, senza interruzione |
| `set_preset` | `"low"` \| `"standard"` \| `"high"` | LOW 720p/25/2 Mbps, STANDARD 1080p/30/5 Mbps, HIGH 1080p/30/7 Mbps, adattati all'hardware |
| `set_record` | booleano | registrazione MP4 locale di backup (serve ≥1 GB libero) |

Il server rifiuta subito (`status: "rejected"`, `error.code: "unsupported"`) i comandi che le
capabilities dichiarate dal telefono non supportano; il telefono ricontrolla comunque.

### Ciclo di vita di un comando

```
Control Room ──command──► Worker: valida, registra (status "sent"), aggiunge seq/sentAt/expiresAt
Worker ──command──► telefono: CommandGuard (id già visto? seq crescente? scaduto?)
telefono ──ack stage=received──► Worker (status "received")
telefono esegue davvero il comando sul motore
telefono ──ack stage=completed ok=true|false, result|error──► Worker (status "completed"/"failed")
Worker ──command_status──► tutte le Control Room collegate
```

Stati: `sent`, `received`, `completed`, `failed`, `rejected`, `timeout`.

- `commandId` già usato → `rejected` / `duplicate_command` (anti-replay lato server).
- `issuedAt` oltre ±120 s dall'orologio del server → `rejected` (orologio del PC sbagliato o replay).
- telefono non collegato → `failed` / `camera_offline`, subito (niente code).
- nessun ACK `completed` entro 25 s → `timeout` / `ack_timeout`.
- il telefono si scollega con comandi in corso → `failed` / `camera_disconnected`.
- sul telefono: `expiresAt` = `sentAt` + 15 s; `seq` deve crescere all'interno della
  connessione; gli ultimi 512 `commandId` eseguiti sono ricordati.

Esempio (da `docs/protocol-fixtures`):

```json
{"v":1,"type":"command","commandId":"3f1c2a9e-5b7d-4c1e-9a2b-6d8e0f1a2b3c","cameraId":"cam_0a1b2c3d4e5f6a7b","command":"set_zoom","value":2.5,"issuedAt":1790000000000}
{"v":1,"type":"command","commandId":"3f1c2a9e-5b7d-4c1e-9a2b-6d8e0f1a2b3c","seq":42,"command":"set_zoom","value":2.5,"issuedAt":1790000000000,"sentAt":1790000000150,"expiresAt":1790000015150,"issuedBy":"Regia"}
{"v":1,"type":"ack","commandId":"3f1c2a9e-5b7d-4c1e-9a2b-6d8e0f1a2b3c","stage":"received","ok":true,"result":null,"error":null,"ts":1790000000200}
{"v":1,"type":"ack","commandId":"3f1c2a9e-5b7d-4c1e-9a2b-6d8e0f1a2b3c","stage":"completed","ok":true,"result":{"zoom":2.5},"error":null,"ts":1790000000260}
```

## Capabilities, stato e telemetria

- `capabilities`: per lente (`back`/`front`) disponibilità, zoom (min/max), torcia,
  autofocus, punto di fuoco, esposizione (min/max/step), FPS supportati per risoluzione;
  risoluzioni, registrazione, protocolli, bitrate massimo dell'encoder. La Control Room
  **disabilita** i controlli non supportati.
- `state`: `cameraStatus`, `streamStatus`, `paused`, `facing`, `zoom`, `torch`,
  `autofocus`, `exposure`, `videoEnabled`, `audioEnabled`, `recording`, `resolution`, `fps`,
  `bitrateMode`, `targetBitrateKbps`, `protocol`, `orientation`, `lastError`.
- `telemetry`: stato stream, rete (tipo, a consumo, validata, uplink stimato), bitrate
  misurato e upload, congestione della coda, FPS, risoluzione, batteria (%, carica,
  temperatura), stato termico, lente, zoom, torcia, microfono, video/audio abilitati,
  uptime, numero di riconnessioni, ultimi errori, registrazione (attiva, spazio libero).

## API HTTP del Worker

| Metodo e percorso | Auth | Scopo |
| --- | --- | --- |
| `GET /api/health` | — | stato del servizio (`streamConfigured`) |
| `POST /api/auth/login` | Origin | `{ "password", "operator" }` → cookie di sessione |
| `POST /api/auth/logout` · `GET /api/auth/me` | cookie | |
| `GET /api/config` | cookie | configurazione pubblica (nessun segreto) |
| `POST /api/pair/start` | — (rate limit) | il telefono chiede un codice: `{ deviceName, model, appVersion }` → `{ pairingId, code, pollToken, expiresAt, pollIntervalMs }` |
| `POST /api/pair/poll` | `Bearer <pollToken>` | `{ pairingId }` → `pending` \| `expired` \| `consumed` \| `paired` (+ `deviceToken`, `cameraId`, `cameraName`, `slot`) |
| `POST /api/cameras/claim` | cookie + Origin | la regia inserisce `{ code, name, slot }` → crea camera e live input |
| `GET /api/cameras` | cookie | elenco camere |
| `PATCH /api/cameras/:id` | cookie + Origin | rinomina / cambia slot |
| `DELETE /api/cameras/:id` | cookie + Origin | revoca il dispositivo |
| `GET /api/cameras/:id/playback` | cookie | URL SRT/RTMPS playback per OBS (evento di audit) |
| `POST /api/cameras/:id/live-input` | cookie + Origin | `{ "action": "create" \| "enable" \| "disable" \| "rotate" \| "refresh" }` |
| `GET /api/events?limit=&cameraId=` | cookie | log di regia |
| `POST /api/webhooks/stream` | header `cf-webhook-auth` | eventi Live di Cloudflare (opzionale) |
