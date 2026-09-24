# android-compile-check

Verifica dei sorgenti Kotlin nativi dell'app **senza Android SDK**, per ambienti
in cui `dl.google.com` (SDK e Google Maven) o `jitpack.io` non sono raggiungibili.
Si esegue con:

```bash
scripts/check_android_sources.sh
```

Cosa fa:

1. scarica i sorgenti di **RootEncoder 2.8.1** (stesso tag usato dall'app) in `build/rootencoder-src`;
2. genera stub delle classi `R` di RootEncoder (`gen_rootencoder_r.py`);
3. compila con Gradle + Kotlin 2.4.0 **il codice dell'app e RootEncoder** contro:
   - `org.robolectric:android-all:16-robolectric-13921718` (framework Android 16, API 36, da Maven Central);
   - `flutter.jar` dell'SDK Flutter locale (`io.flutter.*`);
   - le stesse dipendenze di RootEncoder (kotlinx-coroutines 1.11.0, ktor-network 3.5.2, Bouncy Castle 1.84);
4. controlla il bytecode (`check_public_api.py`):
   - ogni riferimento `android.*` deve esistere nelle firme **pubbliche** di Android 16
     (`core/api/current.txt` di frameworks/base e dei moduli Connectivity, Wi-Fi e MediaProvider,
     dal mirror GitHub di LineageOS `lineage-23.0`): android-all contiene anche API nascoste;
   - ogni API più recente di **minSdk 26** deve essere elencata in `min_sdk_baseline.txt`
     insieme al controllo `Build.VERSION.SDK_INT` che la protegge (firma API 26 dal mirror AOSP
     `android-8.0.0_r1`). I metodi ereditati (es. `startForeground` su `Service`,
     `getDisplay` via `FlutterActivity`) sono risolti risalendo la gerarchia delle classi.

Cosa **non** fa (resta compito di `scripts/build_android.sh`, cioè della build Gradle reale):
merge del manifest, compilazione delle risorse (`aapt2`), classi `R`/`BuildConfig` reali
(qui sono stub), D8/R8, firma e impacchettamento dell'APK, lint Android completo.
Le costanti `static final` sono inglobate dal compilatore e non compaiono nel bytecode.

File:

| File | Scopo |
| --- | --- |
| `build.gradle.kts`, `settings.gradle.kts` | progetto Gradle JVM di sola compilazione |
| `stubs/` | stub di `androidx.annotation`, `androidx.lifecycle` (supertipi di `FlutterActivity`), `R`/`BuildConfig` dell'app |
| `gen_rootencoder_r.py` | stub delle classi `R` di RootEncoder |
| `check_public_api.py` | controllo API pubbliche + minSdk |
| `min_sdk_baseline.txt` | usi revisionati di API > 26, con la relativa guardia |
