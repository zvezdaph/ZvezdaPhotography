# Associazione telefono ↔ regia

L'associazione collega un telefono a uno **slot** della regia (CAM 01, CAM 02, …) senza
scambiare password, IP o chiavi a mano. Funziona ovunque ci sia Internet: telefono e PC non
devono stare sulla stessa rete.

## Procedura

**Sul telefono**

1. Apri **PeopleCare Remote Camera** → schermata **ASSOCIA ALLA REGIA**.
2. Controlla **Indirizzo della regia** (precompilato se l'APK è stato compilato con
   `CONTROL_PLANE_URL`) e **Nome del telefono**.
3. Tocca **GENERA CODICE**: compaiono un codice come `7KQ4-M2XD`, il relativo **QR** e il
   tempo residuo (10 minuti, `PAIRING_TTL_MINUTES`).

**Nella Control Room (PC)**

4. Accedi con la password della regia → **Aggiungi camera** (o il riquadro di uno slot libero).
5. Digita il codice (maiuscole/minuscole, trattino, `O`/`0` e `I`/`L`/`1` sono equivalenti)
   oppure **Scansiona QR** con la webcam.
6. Scegli lo **slot** e il **nome**, ad esempio `CAM 01 - SALA`, `CAM 02 - PALCO`
   (i suggerimenti rapidi compilano il nome) → **Associa camera**.

**Risultato**

7. Il Worker crea la camera e il suo **live input** Cloudflare. Il telefono, che interroga il
   server ogni 3 secondi, riceve il proprio **token dispositivo**, lo salva nello storage cifrato
   (Android Keystore) e si collega alla regia: la camera appare **online** nella dashboard.

Da quel momento il telefono ricorda la regia: ai successivi avvii si ricollega da solo.

## Come funziona

```
Telefono                                   Worker (Durable Object)                 Control Room
POST /api/pair/start {deviceName,…} ─────► crea pairing: hash(codice), hash(pollToken),
◄───── {pairingId, code, pollToken, expiresAt}      scadenza 10 min
mostra codice + QR "PCRC:1:<CODICE>:<host>"
POST /api/pair/poll (Bearer pollToken) ──► "pending" …
                                                                       ◄── POST /api/cameras/claim
                                            verifica codice (hash), slot libero,  {code, name, slot}
                                            crea camera + live input Cloudflare
POST /api/pair/poll ─────────────────────► "paired" + deviceToken (nuovo a ogni poll,
◄───── {cameraId, cameraName, slot, deviceToken}   vale solo l'ultimo)
WSS /ws/device (Bearer deviceToken) ─────► camera attivata, pairing cancellato ──► camera online
```

- Il **QR** contiene solo `PCRC:1:<CODICE>:<host della regia>`: nessun segreto oltre al codice
  monouso che è già visibile sullo schermo.
- Il codice ha 8 caratteri dell'alfabeto Crockford base32 (40 bit), è **monouso** e **scade**;
  il server conserva solo l'hash. Codici sbagliati e richieste eccessive sono limitati per IP
  (10 richieste di codice e 10 login ogni 10 minuti) e per sessione di regia (20 tentativi di
  associazione ogni 10 minuti), oltre al rate limit all'edge.
- Il `pollToken` impedisce che altri leggano l'esito dell'associazione conoscendo solo il codice.
- Il **token dispositivo** (256 bit) viaggia una sola volta via HTTPS, è salvato cifrato sul
  telefono e sul server solo come hash SHA-256. Va sempre nell'header `Authorization`, mai
  nell'URL.
- Il telefono non riceve mai credenziali Cloudflare dell'account: riceve dal Worker solo le
  credenziali di trasmissione del proprio live input.

## Rinominare, spostare, revocare

- **Rinomina / cambia slot**: dal dettaglio camera nella Control Room; il telefono riceve il
  nuovo nome subito (`camera_info`).
- **Revoca dispositivo**: dal dettaglio camera. Il telefono viene disconnesso (codice 4001),
  il token invalidato, i comandi in corso falliscono e il live input viene trattato secondo
  `REVOKE_ACTION` (predefinito `rotate`: chiavi ruotate, le vecchie credenziali non funzionano
  più). Il telefono torna alla schermata di associazione con il messaggio "revocato dalla regia".
- **Dissocia** dal telefono (Diagnostica → DISSOCIA): il telefono dimentica la regia; per
  invalidare anche il token sul server usa *Revoca dispositivo* nella Control Room.
- **Telefono perso o rubato**: revocalo dalla Control Room; il token smette subito di funzionare.

## Problemi comuni

| Messaggio | Soluzione |
| --- | --- |
| "Codice non trovato o scaduto" | genera un nuovo codice sul telefono (scade dopo 10 minuti ed è monouso) |
| "Lo slot CAM 0x è già occupato" | scegli un altro slot o revoca la camera che lo occupa |
| il telefono resta "In attesa della regia" | il codice non è stato inserito, oppure il telefono non raggiunge l'indirizzo della regia (controlla l'URL e la connessione) |
| "Troppe richieste" | attendi qualche minuto (limite anti-abuso) |
| la camera è associata ma senza live input | Cloudflare non configurato o token API senza permesso Stream: vedi [CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md), poi *Crea live input* dal dettaglio camera |
