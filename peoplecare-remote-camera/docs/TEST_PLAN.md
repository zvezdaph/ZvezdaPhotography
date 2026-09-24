# Piano di test

## 1. Test automatici

Tutti insieme: `scripts/test_all.sh` (aggiungi `--native` per la verifica dei sorgenti Kotlin).

| Componente | Comando | Contenuto |
| --- | --- | --- |
| Worker | `cd cloudflare/worker && npm run typecheck && npm test` | Vitest 4 nel runtime reale `workerd` (`@cloudflare/vitest-plugin`), Durable Object e WebSocket veri; solo l'API di Cloudflare è simulata (vedi §3) |
| Control Room | `cd apps/control_room && npm run typecheck && npm test && npx vite build` | Vitest su reducer, logica dei controlli, invio comandi, backoff, formattazione |
| App (Dart) | `cd apps/remote_camera && flutter analyze && flutter test` | test unitari e di integrazione del livello Dart con trasporto e motore finti |
| App (Kotlin) | `scripts/check_android_sources.sh` | compilazione di app + RootEncoder 2.8.1 contro android-all API 36, solo API pubbliche, guardie per minSdk 26 |
| End-to-end locale | `tools/e2e/run_e2e.sh` | Worker in `wrangler dev` + Control Room in Chromium (Playwright) + livello Dart reale del telefono: pairing, comandi con ACK, stati, URL OBS (API Stream simulata, motore camera simulato; vedi `tools/e2e/README.md`) |

Copertura per requisito:

| Requisito | Test |
| --- | --- |
| Protocollo JSON versionato con ACK | fixture condivise in `docs/protocol-fixtures` verificate da `worker/test/protocol.spec.ts`, `remote_camera/test/protocol_test.dart` e dalla Control Room: parsing, ACK identici, validatori per ogni comando, stessi valori invalidi rifiutati |
| Nessun ACK simulato | Worker: "delivers a command to the phone and relays the real ACK", "fails immediately when the phone is offline (no fake ACK)", "times out commands that the phone never acknowledges"; Dart: "executes a remote command and acknowledges the real result", "reports engine failures in the ACK" |
| Anti-replay | Worker: "rejects replayed command ids", "rejects commands issued too far in the future"; Dart `command_guard_test.dart` (id ripetuti, sequenze, scadenza con orologio del server) |
| Pairing | Worker: codice monouso, slot occupati, token consegnato solo dopo la conferma, pairing invisibile ad altri; Dart `pairing_test.dart`: HTTPS obbligatorio, formato QR, polling, errori di rete, salvataggio solo nello storage sicuro |
| Parsing della configurazione | Dart `config_parsing_test.dart`: configurazione del control plane, cache cifrata, niente segreti nelle descrizioni, endpoint malformati, preset adattati all'hardware |
| Reconnect policy | Dart `reconnect_policy_test.dart`, `control_client_test.dart` (backoff, heartbeat su connessioni half-open, revoca 4001, token revocato con probe 401); Control Room `reconnect.spec.ts` |
| Gestione degli stati | Dart `state_management_test.dart`: LIVE solo se il trasporto è davvero connesso, stati del collegamento, spie, telemetria, revoca; Control Room `controls.spec.ts`: LIVE solo se il telefono lo riporta, controlli disabilitati senza capabilities |
| Sicurezza della regia | Worker: password errata, Origin non valido, cookie `HttpOnly`/`SameSite=Strict`, rate limit sui tentativi, WebSocket rifiutati senza sessione |
| Cloudflare Stream API | Worker `stream.spec.ts`: corpo e metodi documentati (POST/GET/PUT/DELETE, `rotate_keys`), token mai nei messaggi d'errore, URL OBS, mappatura degli stati, webhook |
| Segreti mai esposti | Worker: "sends the SRT ingest configuration only to the phone", "exposes a health endpoint without secrets"; Dart `diagnostics_test.dart`: report e log senza token/passphrase/chiavi |

## 2. Collaudo manuale end-to-end

Prerequisiti: Worker pubblicato con i secret (vedi [CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md)),
APK installato su almeno due telefoni, OBS configurato ([OBS_SETUP.md](OBS_SETUP.md)).
Per ogni prova annota: esito, tempi, modello del telefono e versione di Android, report
diagnostico se qualcosa non va.

### A. Pairing e sicurezza

| # | Prova | Atteso |
| --- | --- | --- |
| A1 | GENERA CODICE sul telefono, inserimento in Control Room su CAM 01 | camera online in < 5 s, live input creato (dettaglio → Cloudflare) |
| A2 | Scansione del QR con la webcam | codice riconosciuto e inserito |
| A3 | Riutilizzo dello stesso codice su un altro slot | "Codice non trovato o scaduto" |
| A4 | Attesa di 10 minuti senza inserire il codice | il telefono mostra "Codice scaduto" |
| A5 | Revoca dispositivo | telefono disconnesso, torna ad ASSOCIA ALLA REGIA con messaggio di revoca; il vecchio URL SRT di trasmissione non funziona più |
| A6 | Login con password errata 11 volte | blocco temporaneo (429) |
| A7 | Riavvio del telefono dopo l'associazione | ricollegamento automatico senza nuovo pairing |

### B. Streaming

| # | Prova | Atteso |
| --- | --- | --- |
| B1 | START dal telefono | LIVE rosso sul telefono solo dopo la connessione; CLOUDFLARE LIVE in Control Room entro il poll/webhook; immagine in OBS |
| B2 | START/STOP dalla Control Room | ACK `received` e `completed`; stato coerente su telefono e regia |
| B3 | Latenza OBS | cronometro inquadrato: misura glass-to-glass SRT → OBS (atteso: sotto pochi secondi, tipicamente meno con latenza SRT bassa) |
| B4 | PAUSE / RESUME | OBS mostra nero e silenzio senza perdere la connessione; ripresa immediata con keyframe |
| B5 | VIDEO OFF / AUDIO OFF separati | solo la traccia interessata viene oscurata/silenziata |
| B6 | Preset LOW / STANDARD / HIGH | risoluzione/FPS/bitrate applicati se supportati; altrimenti adattati e segnalati nel log |
| B7 | Bitrate MANUALE durante la diretta | cambia senza interruzione |
| B8 | Cambio risoluzione durante la diretta | breve interruzione, poi LIVE |
| B9 | Diretta di 2 ore con caricatore | nessuna interruzione, temperatura e batteria in telemetria |
| B10 | Schermo spento / DIM / app in background | la diretta continua; notifica persistente con STOP DIRETTA |

### C. Rete e riconnessione

| # | Prova | Atteso |
| --- | --- | --- |
| C1 | Wi-Fi → 4G durante la diretta | RECONNECTING, poi LIVE sulla nuova rete in pochi secondi; OBS riprende da solo (Reconnect Delay 1 s) |
| C2 | Modalità aereo per 30 s, poi disattivata | RECONNECTING con backoff, poi LIVE; telemetria "riconnessioni" +1 |
| C3 | UDP bloccato (rete che filtra SRT) | dopo 3 tentativi SRT falliti passa a RTMPS (FALLBACK RTMPS) se abilitato |
| C4 | Regia irraggiungibile ma Cloudflare raggiungibile | la diretta continua con la configurazione in cache; REGIA rossa; ricollegamento automatico |
| C5 | Stop forzato del flusso lato Cloudflare (disabilita live input) | il telefono segnala l'errore; la Control Room mostra "disabled" |
| C6 | Telefono LIVE ma Cloudflare scollegato (es. rete che blocca in modo silenzioso) | il watchdog del server invia `reconnect` (evento "watchdog" nel log) |

### D. Controlli remoti e capabilities

| # | Prova | Atteso |
| --- | --- | --- |
| D1 | Zoom (slider, +/−), cambio camera, torcia, autofocus, punto di fuoco, esposizione dalla regia | eseguiti con ACK `completed` e risultato reale |
| D2 | Torcia con camera frontale | comando rifiutato come "non supportato"; pulsante disattivato in Control Room |
| D3 | 60 fps su un telefono che non li supporta | opzione disattivata; il comando forzato viene rifiutato |
| D4 | RECORD BACKUP ON/OFF | file MP4 in Movies/PeopleCare (Android 10+), spazio libero mostrato |
| D5 | Due Control Room aperte | entrambe vedono stato, comandi ed eventi in tempo reale |

### E. Diagnostica

| # | Prova | Atteso |
| --- | --- | --- |
| E1 | COPIA REPORT DIAGNOSTICO e incolla in un editor | nessun token, password, passphrase, streamid o chiave nel testo |
| E2 | Endpoint di test verso `ffplay -fflags nobuffer 'srt://0.0.0.0:9000?mode=listener'` | immagine in ffplay senza Cloudflare |

## 3. Parti simulate nei test automatici (dichiarazione)

- **Cloudflare Stream API**: nei test del Worker le chiamate a `api.cloudflare.com` sono
  intercettate con un finto `fetch` che risponde con la forma documentata dell'API (live input
  con `srt`, `srtPlayback`, `rtmps`, `rtmpsPlayback`, `status`). Serve perché le credenziali
  reali non possono stare nel repository. Tutto il resto (Durable Object, SQLite, WebSocket,
  rate limit, cookie) gira nel runtime reale `workerd`.
- **Motore nativo e WebSocket nei test Dart**: `FakeEngineBridge` e `FakeTransport` sostituiscono
  il MethodChannel e il socket per testare il livello Dart; non generano video e non producono
  ACK da soli.
- Nessuna parte dell'app o del Worker contiene simulazioni: in produzione tutti i percorsi
  usano camera, encoder, rete e API reali.
