# Verifica end-to-end locale

```bash
tools/e2e/run_e2e.sh
```

Esegue senza account Cloudflare il percorso completo del **piano di controllo**:

| Parte | Cosa gira | Reale / simulato |
| --- | --- | --- |
| Worker + Durable Object | `wrangler dev` (workerd, SQLite, WebSocket Hibernation, rate limit locale) | reale |
| API Cloudflare Stream | `mock-cloudflare-api.mjs` (live input con i campi documentati, nessun video) | **MOCK** dichiarato: le credenziali reali non possono stare nel repository |
| Control Room | build Vite servita dal Worker, pilotata in Chromium headless (`control-room.e2e.mjs`, Playwright) | reale |
| Telefono | `apps/remote_camera/test_e2e/phone_e2e_test.dart`: pairing HTTP, `AppController`, `ControlClient` su WebSocket `dart:io`, `CommandGuard`, `CommandExecutor` | reale, tranne il motore camera (simulato: registra le chiamate e pubblica lo stato, nessun video) |

Scenario: login → pairing con il codice generato dal telefono → camera ONLINE → START (ACK
reale, LIVE solo quando il telefono lo riporta) → Zoom + → torcia → camera frontale (torcia
disabilitata dalle capabilities) → posteriore → PAUSE/RESUME → stato Cloudflare "connected"
dal polling del Worker → URL SRT per OBS → STOP → disconnessione del telefono (OFFLINE).
Il telefono verifica di aver ricevuto i comandi nell'ordine, di aver usato le credenziali SRT
consegnate dal Worker e che il report diagnostico non contenga token né segreti SRT.

Screenshot e log in `build/e2e/`. Porte usate: 8787 (Worker) e 8788 (mock).
Non verifica: camera, encoder e trasmissione SRT reali (servono un telefono e un account
Cloudflare: vedi `docs/TEST_PLAN.md`).
