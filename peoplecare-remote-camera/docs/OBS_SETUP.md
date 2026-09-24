# OBS Studio su Ubuntu: ricevere le camere in SRT

OBS riceve ogni camera direttamente da **Cloudflare Stream** tramite l'URL **SRT playback**
del live input: è il percorso a latenza più bassa (Cloudflare documenta per il playback
SRT/RTMPS nelle app basate su ffmpeg una latenza "glass-to-glass" sotto il secondo).
L'anteprima nella Control Room (HLS/LL-HLS) ha invece alcuni secondi di ritardo ed è solo di
controllo. OBS non ha bisogno della rete del telefono: basta l'accesso a Internet del PC.

## 1. Installare OBS

```bash
sudo add-apt-repository ppa:obsproject/obs-studio
sudo apt update && sudo apt install obs-studio ffmpeg
ffmpeg -hide_banner -protocols | grep -w srt   # deve stampare "srt": FFmpeg con libsrt
```

La Sorgente multimediale di OBS usa FFmpeg (libavformat con libsrt) per aprire gli URL
`srt://`. In alternativa è disponibile il Flatpak ufficiale `com.obsproject.Studio`.

## 2. Copiare l'URL SRT dalla Control Room

1. Apri la Control Room → clicca sulla camera (es. **CAM 01 - SALA**).
2. Sezione **OBS · SRT playback** → **Mostra URL SRT per OBS** → **Copia URL OBS**.

L'URL è composto dal Worker con i campi `srtPlayback.url`, `srtPlayback.streamId` e
`srtPlayback.passphrase` restituiti dall'API di Cloudflare per quel live input:

```
srt://<host>:<porta>?passphrase=<passphrase-di-playback>&streamid=<streamid-di-playback>
```

Sono credenziali di **sola visione**, diverse da quelle di trasmissione del telefono. La loro
visualizzazione viene registrata nel log di regia. Trattale come una password: chiunque le
abbia può vedere la camera. Dopo **Ruota chiavi** o **Revoca dispositivo** ricopiale dalla
Control Room.

## 3. Creare la Sorgente multimediale

Scena → **Fonti** → **+** → **Sorgente multimediale** (*Media Source*) → nome, es. `CAM 01 - SALA`.

| Campo (IT) | Campo (EN) | Valore consigliato | Perché |
| --- | --- | --- | --- |
| File locale | Local File | **disattivato** | mostra i campi per le sorgenti di rete |
| Input | Input | l'URL `srt://…` copiato | |
| Formato dell'input | Input Format | vuoto (rilevamento automatico) | facoltativo: `mpegts` evita il rilevamento del contenitore |
| Buffering della rete | Network Buffering | **0 MB** | con 0 OBS attiva il flag FFmpeg `nobuffer` (latenza minima); 1–2 MB se l'immagine scatta su reti instabili |
| Ritardo di riconnessione | Reconnect Delay | **1 s** (minimo) | OBS riprova subito quando il telefono torna in onda (default 10 s) |
| Utilizza la decodifica hardware quando disponibile | Use hardware decoding when available | attivato se la GPU lo supporta | meno CPU con più camere |
| Non mostrare nulla quando la riproduzione finisce | Show nothing when playback ends | a scelta | attivo: la sorgente sparisce se il flusso cade (si vede ciò che sta sotto, es. uno slate); disattivo: resta l'ultimo fotogramma |
| Riavvia la riproduzione quando la fonte torna attiva | Restart playback when source becomes active | disattivato | evita una riconnessione a ogni cambio scena |
| Chiudi il file quando la fonte diventa inattiva | Close file when inactive | **disattivato** | tiene la connessione SRT aperta anche fuori onda: stacchi immediati |
| Opzioni FFmpeg | FFmpeg Options | `latency=200000` | latenza di ricezione SRT in **microsecondi** (200 ms); vedi sotto |

Le **Opzioni FFmpeg** accettano coppie `opzione=valore` separate da spazi e sono passate a
FFmpeg all'apertura dell'input (verificato sul codice di OBS, `media-playback/media.c`).
Opzioni utili del protocollo SRT di FFmpeg (`libavformat/libsrt.c`):

| Opzione | Unità | Uso |
| --- | --- | --- |
| `latency` | µs | buffer di ritrasmissione SRT del ricevitore: 120000–200000 su fibra stabile, 500000–1000000 su reti con perdite |
| `connect_timeout` | ms | tempo massimo di connessione (default del caller 3000) |
| `rcvlatency` | µs | come `latency` ma solo lato ricezione |

Opzioni di formato facoltative: `analyzeduration` (µs) e `probesize` (byte) riducono il tempo
di aggancio; valori troppo bassi possono far perdere la traccia audio, quindi usale solo dopo
aver verificato che audio e video arrivano entrambi.

## 4. Più camere

Ripeti la procedura per ogni camera (CAM 01…CAM 04 e oltre): ogni Sorgente multimediale apre
la propria sessione SRT playback. Ogni visione (OBS o anteprima nella Control Room) conta come
minuti consegnati per Cloudflare Stream.

## 5. Verifica rapida con ffplay

Dalla documentazione di Cloudflare (esempio "SRT playback"):

```bash
ffplay -analyzeduration 1 -fflags -nobuffer -probesize 32 -sync ext '<URL SRT copiato>'
```

Se ffplay mostra la camera ma OBS no, il problema è nella configurazione della sorgente.

## 6. Alternativa RTMPS

Se la rete del PC blocca l'UDP in uscita (SRT usa UDP), la Control Room mostra anche l'URL
**RTMPS playback** (`rtmps://…/live/<chiave-di-playback>`, TCP 443): usalo come *Input* della
stessa Sorgente multimediale. La latenza è un po' più alta.

## 7. Problemi comuni

| Sintomo | Verifica |
| --- | --- |
| sorgente nera | nella Control Room la spia **CLOUDFLARE** della camera deve essere LIVE; se il telefono è LIVE ma Cloudflare no, il watchdog chiede la riconnessione in automatico |
| nel log di OBS `Failed to open media` | URL incompleto o chiavi ruotate: ricopialo; UDP in uscita bloccato dal firewall della sede |
| `Protocol not found` | l'FFmpeg usato da OBS non ha libsrt: installa OBS dal PPA ufficiale o il Flatpak |
| immagine che scatta | aumenta `latency` (es. `latency=500000`) o il *Buffering della rete* |
| ritardo che cresce nel tempo | *Buffering della rete* a 0 e *Restart playback* disattivato; controlla il carico della CPU/GPU |
| audio assente | l'audio della camera può essere disattivato dalla regia o dal telefono, oppure il permesso microfono è negato (il telefono trasmette silenzio e lo segnala nella diagnostica) |

Il log di OBS è in **Aiuto → File di log** (*Help → Log Files*).
