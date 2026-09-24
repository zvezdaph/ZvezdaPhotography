# App Android: compilazione, installazione e uso

App: **PeopleCare Remote Camera** · package `tv.peoplecare.remotecamera` · Android 8.0+
(minSdk 26), target Android 16 (API 36). Un solo motore nativo (RootEncoder 2.8.1) gestisce
camera, anteprima, codifica H.264/AAC con MediaCodec e trasmissione SRT/RTMPS.

## 1. Toolchain

| Strumento | Versione usata/verificata |
| --- | --- |
| Flutter (stable) | 3.47.5 (Dart 3.13.4) |
| JDK | 17 o 21 |
| Android SDK | Platform 36, Build-Tools, Platform-Tools (Android Studio o `sdkmanager`) |
| Gradle / Android Gradle Plugin / Kotlin | 9.3.1 / 9.1.0 / 2.4.0 (dal template Flutter, wrapper incluso) |

```bash
flutter doctor                     # deve riconoscere l'Android toolchain
flutter doctor --android-licenses  # accetta le licenze dell'SDK
```

La build scarica dipendenze da: `dl.google.com` (Google Maven e SDK), `repo.maven.apache.org`
(Maven Central), **`jitpack.io`** (RootEncoder), `services.gradle.org`, `plugins.gradle.org`,
`storage.googleapis.com` (artefatti del motore Flutter) e `pub.dev`. Se `jitpack.io` non è
raggiungibile ma Google Maven sì, usa `scripts/build_rootencoder_from_source.sh` (sotto).

## 2. Compilare l'APK

```bash
cp .env.example .env    # imposta CONTROL_PLANE_URL=https://<worker>.<sottodominio>.workers.dev
scripts/build_android.sh            # debug  → dist/peoplecare-remote-camera-debug.apk
scripts/build_android.sh release    # release (configura prima una keystore, vedi sotto)
```

Lo script esegue `flutter pub get`, `flutter analyze`, `flutter test` e
`flutter build apk --debug --dart-define=CONTROL_PLANE_URL=…`. L'indirizzo della regia
compilato nell'APK è solo il valore predefinito: si può cambiare nella schermata di
associazione.

Build manuale equivalente (Gradle diretto):

```bash
cd apps/remote_camera
flutter pub get                    # scrive android/local.properties con flutter.sdk
cd android && ./gradlew assembleDebug
# APK: apps/remote_camera/build/app/outputs/apk/debug/app-debug.apk
```

Con `./gradlew` non viene passato `CONTROL_PLANE_URL`: l'indirizzo si inserisce nell'app.

**RootEncoder senza JitPack** (richiede comunque Google Maven e un JDK 17):

```bash
ANDROID_HOME=$HOME/Android/Sdk scripts/build_rootencoder_from_source.sh   # → build/rootencoder-maven
ROOTENCODER_MAVEN_REPO=$PWD/build/rootencoder-maven scripts/build_android.sh
```

**Verifica dei sorgenti Kotlin senza Android SDK** (compilazione contro android-all API 36 e
controllo delle sole API pubbliche e del minSdk): `scripts/check_android_sources.sh`
(dettagli in `tools/android-compile-check/README.md`).

**Release firmata**: crea una keystore (`keytool -genkeypair -v -keystore peoplecare.jks
-alias peoplecare -keyalg RSA -keysize 4096 -validity 3650`), aggiungi un `signingConfig` in
`android/app/build.gradle.kts` che legga `android/key.properties` (file ignorato da git) e
sostituisci la firma di debug del blocco `release`.

## 3. Installare sul telefono

1. Sul telefono: Impostazioni → Info telefono → tocca 7 volte *Numero build* → Opzioni
   sviluppatore → **Debug USB**.
2. Dal PC: `adb install -r dist/peoplecare-remote-camera-debug.apk`

In alternativa copia l'APK sul telefono e consenti l'installazione da origini sconosciute
per l'app con cui lo apri.

## 4. Primo avvio

1. Concedi **Fotocamera**, **Microfono** e **Notifiche** (Android 13+). Senza microfono l'app
   trasmette audio silenzioso e lo segnala; senza fotocamera non può trasmettere.
2. Schermata **ASSOCIA ALLA REGIA**: controlla l'indirizzo della regia e il nome del
   telefono → **GENERA CODICE**. Inserisci il codice (o fai scansionare il QR) nella Control
   Room: vedi [PAIRING.md](PAIRING.md).
3. A associazione completata compare la schermata camera; la spia **REGIA** diventa verde e la
   Control Room vede la camera online.

Impostazioni consigliate del telefono: batteria dell'app **Senza restrizioni** (Impostazioni →
App → PeopleCare Remote Camera → Batteria), caricatore collegato per dirette lunghe, *Non
disturbare* attivo, Wi‑Fi a 5 GHz o rete mobile con buon upload.

## 5. Schermata camera

- Anteprima a tutto schermo (texture Flutter dal motore nativo, stessa immagine trasmessa).
- Stato: **LIVE** (rosso, solo quando la connessione SRT/RTMPS è confermata), **RECONNECTING**,
  **OFFLINE**, **ERROR**, con uptime, bitrate, FPS, protocollo e numero di riconnessioni.
- Spie **CAMERA** · **CLOUDFLARE** (stato dell'ingest visto da Cloudflare) · **REGIA**
  (WebSocket di controllo).
- Pulsanti grandi: **START**, **PAUSE/RESUME** (video nero e audio muto mantenendo la sessione
  SRT), **STOP** (con conferma).
- Strumenti: **FRONT/BACK**, **TORCIA**, **MUTE/UNMUTE**, **VIDEO ON/OFF**, **AUTOFOCUS**,
  **BACKUP ON/OFF** (registrazione MP4 locale), **IMPOSTA** (preset LOW/STANDARD/HIGH,
  risoluzione, FPS, bitrate AUTO/MANUALE, esposizione, orientamento LANDSCAPE/PORTRAIT LOCK,
  schermo sempre acceso, fallback RTMPS), **DIM** (oscura lo schermo durante la diretta),
  **DIAGNOSI**.
- Zoom con slider e pinch, tocco sull'anteprima per il punto di fuoco.
- I controlli non supportati dall'hardware sono disattivati (vedi sotto).

La diretta continua a **schermo spento** e con l'app in background grazie al servizio in
foreground (notifica persistente con **STOP DIRETTA**). Se chiudi l'app dal multitasking
mentre non sei in diretta né in registrazione, il servizio rilascia la camera e la regia vede
la camera offline; durante una diretta il servizio resta attivo.

## 6. Preset e funzioni per dispositivo

| Preset | Risoluzione | FPS | Bitrate video |
| --- | --- | --- | --- |
| LOW | 720p | 25 | 2 Mbps |
| STANDARD | 1080p | 30 | 5 Mbps |
| HIGH | 1080p | 30 | 7 Mbps |

I preset vengono **adattati all'hardware**: se una combinazione non è supportata si usa la più
vicina disponibile e l'app lo registra nel log. Audio AAC 128 kbps 48 kHz stereo (ripiego
44,1 kHz / mono se il microfono non lo supporta), GOP 2 s come consigliato da Cloudflare (2–8 s).

| Funzione | Disponibile quando |
| --- | --- |
| 50/60 fps | la camera dichiara il range FPS **e** l'encoder H.264 supporta risoluzione×FPS |
| 1080p | l'encoder e la camera supportano 1920×1080 |
| Torcia | la lente attiva ha il flash (tipicamente solo la posteriore) |
| Zoom ottico/ratio | Android 11+ con camera non LEGACY (`CONTROL_ZOOM_RATIO_RANGE`); altrimenti zoom digitale |
| Punto di fuoco | la lente ha regioni AF (`CONTROL_MAX_REGIONS_AF > 0`) |
| Esposizione | range di compensazione non nullo |
| Registrazione backup | encoder disponibile e almeno **1 GB** libero (controllato all'avvio) |

Le registrazioni sono scritte in `Android/data/tv.peoplecare.remotecamera/files/Movies/PeopleCare`
e, su Android 10+, spostate alla fine in **Movies/PeopleCare** (MediaStore, senza permessi di
archiviazione). Su Android 8–9 restano nella cartella dell'app.

## 7. Diagnostica

**DIAGNOSI** mostra stato completo (app, dispositivo, camera e stream, regia e Cloudflare),
log filtrabili INFO/WARNING/ERROR e il pulsante **COPIA REPORT DIAGNOSTICO**: il report non
contiene token, password, passphrase, streamid né chiavi (redazione automatica).

Da qui si possono anche: ricaricare la configurazione, spegnere la camera, dissociare il
telefono e impostare un **endpoint di test** (es. `srt://192.168.1.10:9000?streamid=test`)
per collaudare lo streaming verso un server SRT locale senza Cloudflare, ad esempio:

```bash
ffplay -fflags nobuffer 'srt://0.0.0.0:9000?mode=listener'
```

## 8. Limiti noti

- Solo **H.264 + AAC** (requisito di Cloudflare Stream Live); niente HEVC né 4K.
- Android 11+ vieta di avviare la camera da un servizio partito in background: la camera
  viene "armata" aprendo l'app; da quel momento START/STOP remoti funzionano anche a schermo
  spento.
- La verifica su telefoni reali (camere, encoder, termica) non è stata possibile in questo
  ambiente: segui [TEST_PLAN.md](TEST_PLAN.md).
