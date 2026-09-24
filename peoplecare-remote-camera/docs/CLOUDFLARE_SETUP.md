# Configurazione Cloudflare

Il Worker `cloudflare/worker` è il **control plane** (pairing, comandi, stato) e ospita anche
la **Control Room**. È l'unico componente che parla con la **Cloudflare Stream API**: account
ID e token API esistono solo come **secret di Wrangler**, mai nell'APK, nel browser o nel
repository.

## 1. Prerequisiti

- Un account Cloudflare con **Stream** attivo. Dalla documentazione di Stream: i live input
  si possono creare solo dopo aver sottoscritto Stream; lo storage è prepagato (le
  registrazioni delle dirette lo consumano) e, se lo storage finisce, **non si possono avviare
  nuove dirette**. La consegna è a consumo (minuti visti).
- Node.js 22 o superiore e npm (`scripts/setup.sh` controlla le versioni).
- Workers con Durable Objects **SQLite** (inclusi nel piano Workers).

## 2. Credenziali (da tenere fuori dal repository)

| Valore | Dove trovarlo | Dove va |
| --- | --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Dashboard → pagina iniziale dell'account → **Account ID** | secret del Worker |
| `CLOUDFLARE_API_TOKEN` | My Profile → **API Tokens** → *Create Token* → *Create Custom Token*: permesso **Account → Stream → Edit** (nell'API si chiama "Stream Write"), *Account Resources*: solo il tuo account | secret del Worker |
| `CONTROL_ROOM_PASSWORD` | scegline una di almeno 12 caratteri | secret del Worker |
| `STREAM_WEBHOOK_SECRET` | opzionale, una stringa casuale lunga (es. `openssl rand -hex 32`) | secret del Worker + webhook di Cloudflare |
| codice cliente Stream (facoltativo) | pagina **Stream** della dashboard (`customer-<CODE>.cloudflarestream.com`) | variabile `CLOUDFLARE_STREAM_CUSTOMER_CODE` |

Il token serve solo a creare, leggere, abilitare/disabilitare, ruotare le chiavi ed eliminare
i live input delle camere. Non serve alcun permesso di zona/DNS.

## 3. Installazione e configurazione

```bash
scripts/setup.sh                 # npm ci di Worker e Control Room, flutter pub get
cd cloudflare/worker
npx wrangler login               # apre il browser per autorizzare Wrangler
```

In `cloudflare/worker/wrangler.jsonc` controlla:

- `name`: nome del Worker (determina l'URL `https://<name>.<sottodominio>.workers.dev`);
- `vars`: valori predefiniti documentati in `.env.example` (bitrate, latenza SRT,
  `REVOKE_ACTION`, polling, `DO_LOCATION_HINT` vicino alla regia, ecc.);
- `ratelimits[0].namespace_id`: un intero **univoco nel tuo account** (il binding limita
  login, pairing e webhook all'edge; se il tuo piano non lo supporta rimuovi il blocco
  `ratelimits`: restano comunque i limiti interni in SQLite).

## 4. Deploy

```bash
scripts/deploy_cloudflare.sh
```

Lo script compila e testa la Control Room (`apps/control_room/dist`), esegue typecheck e test
del Worker, un `wrangler deploy --dry-run` e poi `wrangler deploy`.

Poi imposta i secret (applicati subito, senza nuovo deploy):

```bash
cd cloudflare/worker
npx wrangler secret put CLOUDFLARE_ACCOUNT_ID
npx wrangler secret put CLOUDFLARE_API_TOKEN
npx wrangler secret put CONTROL_ROOM_PASSWORD
# opzionale
npx wrangler secret put STREAM_WEBHOOK_SECRET
```

Verifica:

```bash
curl -s https://<name>.<sottodominio>.workers.dev/api/health
# {"ok":true,"service":"peoplecare-remote-camera","version":"1.0.0","streamConfigured":true,...}
```

`streamConfigured` è `true` solo quando entrambi i secret dell'API sono impostati (i
placeholder `PLACEHOLDER_…` non contano). Apri l'URL del Worker in Chrome: compare il login
della Control Room.

## 5. Cosa fa il Worker su Cloudflare Stream

Per ogni camera associata crea **un live input** (`POST /accounts/{account_id}/stream/live_inputs`)
con:

- `meta`: nome della camera, `cameraId`, `app`;
- `recording.mode`: `automatic` (predefinito: serve per l'anteprima HLS/Player nella Control
  Room) oppure `off` (`STREAM_RECORDING_MODE`), `requireSignedURLs: false`,
  `hideLiveViewerCount: true`, `allowedOrigins` da `STREAM_ALLOWED_ORIGINS`;
- `deleteRecordingAfterDays` (≥ 30) da `STREAM_DELETE_RECORDING_AFTER_DAYS`;
- `preferLowLatency: true` se `STREAM_PREFER_LOW_LATENCY=true` (LL-HLS, beta di Cloudflare).

Poi legge il live input (`GET …/live_inputs/{uid}`) per:

- consegnare al telefono **solo** le credenziali di ingest (`srt.url`, `srt.streamId`,
  `srt.passphrase` e, come fallback, `rtmps.url` + `rtmps.streamKey`);
- mostrare alla regia, **su richiesta esplicita** e con evento di audit, le credenziali di
  **playback** (`srtPlayback`, `rtmpsPlayback`) per OBS;
- seguire lo stato della connessione (`status`: `connected`, `reconnecting`,
  `client_disconnect`, `failed_to_connect`, …) ogni `CF_POLL_INTERVAL_SECONDS` mentre una camera
  è attiva.

Dalla Control Room (dettaglio camera → Cloudflare) si possono **abilitare/disabilitare** il
live input (`PUT` con `enabled`), **ruotare le chiavi** (`POST …/rotate_keys`: il telefono
riceve subito la nuova configurazione) o crearlo se manca. Alla **revoca** di un dispositivo il
Worker applica `REVOKE_ACTION`: `rotate` (predefinito, le vecchie credenziali smettono di
funzionare), `disable`, `delete` o `none`.

## 6. Webhook Live (opzionale, consigliato)

Senza webhook il Worker usa il polling. Con il webhook la Control Room vede subito
connessioni, disconnessioni ed errori dell'ingest (es. `ERR_GOP_OUT_OF_RANGE`).

1. Dashboard → **Notifications** → **Destinations** → *Webhooks* → **Create**:
   - URL: `https://<name>.<sottodominio>.workers.dev/api/webhooks/stream`
   - Secret: lo stesso valore di `STREAM_WEBHOOK_SECRET` (Cloudflare lo invia nell'header
     `cf-webhook-auth`; il Worker rifiuta le richieste senza secret corretto).
   - **Save and Test**.
2. **Notifications** → **All Notifications** → **Add** → prodotto **Stream** → tipo
   **Stream Live Input** → aggiungi il webhook → **Create** (per tutti i live input o solo per
   quelli indicati).

Eventi gestiti: `live_input.connected`, `live_input.disconnected`, `live_input.errored`
(con codice e messaggio d'errore).

## 7. Dominio personalizzato (opzionale)

Workers & Pages → il Worker → **Settings → Domains & Routes** → *Add → Custom domain*
(es. `regia.example.com`). La Control Room e le API restano sulla stessa origine. Se servi la
Control Room da un'altra origine, aggiungila a `ALLOWED_ORIGINS`. Ricompila l'APK con il
nuovo `CONTROL_PLANE_URL` oppure cambialo nella schermata di associazione.

## 8. Sviluppo locale

```bash
cd cloudflare/worker
cp .dev.vars.example .dev.vars   # inserisci i tuoi valori (file ignorato da git)
npx wrangler dev                 # http://localhost:8787
cd ../../apps/control_room && npm run dev   # http://localhost:5173 (proxy verso :8787)
```

Per provare il telefono contro `wrangler dev` sulla rete di casa usa
`npx wrangler dev --ip 0.0.0.0` e compila un APK di debug con
`CONTROL_PLANE_URL=http://<ip-del-pc>:8787 ALLOW_INSECURE_CONTROL_PLANE=true scripts/build_android.sh`.
È solo per sviluppo: in produzione la regia è raggiungibile esclusivamente via HTTPS/WSS.

## 9. Problemi comuni

| Sintomo | Causa probabile |
| --- | --- |
| `/api/health` → `streamConfigured: false` | secret `CLOUDFLARE_ACCOUNT_ID`/`CLOUDFLARE_API_TOKEN` mancanti o placeholder |
| "Live input Cloudflare non creato" all'associazione | token senza permesso *Stream Edit* o Stream non attivo; la camera viene creata comunque, usa *Crea live input* dal dettaglio |
| login: `not_configured` | `CONTROL_ROOM_PASSWORD` mancante o più corta di 12 caratteri |
| login: `bad_origin` | Control Room aperta da un'origine non elencata in `ALLOWED_ORIGINS` |
| anteprima assente nella Control Room | nessuna registrazione ancora creata (il codice cliente viene rilevato dal primo video) oppure `STREAM_RECORDING_MODE=off`; imposta `CLOUDFLARE_STREAM_CUSTOMER_CODE` |
| ingest in errore `ERR_MISSING_SUBSCRIPTION` / `ERR_STORAGE_QUOTA_EXHAUSTED` | abbonamento Stream o storage esaurito |
