# LiveKit PRE-LIVE realtime

B2 separa due percorsi:

- **PRE-LIVE**: telefono -> LiveKit/WebRTC -> Control Room. Serve per inquadrare prima di START.
- **PROGRAM**: START rilascia la camera LiveKit e la passa a RootEncoder -> SRT -> Cloudflare -> OBS.
- **STOP**: ferma SRT, rilascia RootEncoder e riattiva PRE-LIVE.

Non vengono aperte due capture Android contemporaneamente.

## Configurazione Worker

In `cloudflare/worker/wrangler.jsonc`:

```json
"LIVEKIT_URL": "wss://<progetto>.livekit.cloud",
"LIVEKIT_TOKEN_TTL_SECONDS": "600"
```

I segreti restano solo nel Worker:

```bash
cd cloudflare/worker
npx wrangler secret put LIVEKIT_API_KEY
npx wrangler secret put LIVEKIT_API_SECRET
```

Poi ricostruire Control Room e ridistribuire:

```bash
cd ../..
scripts/build_control_room.sh
scripts/deploy_cloudflare.sh
```

## Sicurezza

Il telefono riceve un token publish-only per la stanza `pcrc-<cameraId>`.
La Control Room riceve un token subscribe-only dopo autenticazione di regia.
API key/secret LiveKit non vengono inviati né all'APK né al browser.

## Accettazione B2

1. Camera ONLINE + PRONTA mostra PRE-LIVE WebRTC prima di START.
2. START produce ACK e passa a SRT senza contesa della camera.
3. Durante PROGRAM, OBS usa SRT playback; HLS è solo verifica uscita.
4. STOP riporta automaticamente il telefono in PRE-LIVE.
5. Front/rear funziona in PRE-LIVE; controlli nativi non compatibili restano disabilitati fino a START.
