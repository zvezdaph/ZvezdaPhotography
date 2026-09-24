# PeopleCare Remote Camera — app Android

App Flutter con motore nativo Kotlin (RootEncoder 2.8.1): camera, anteprima, codifica
H.264/AAC e trasmissione SRT/RTMPS verso Cloudflare Stream, controllata dalla regia tramite
il Worker Cloudflare.

- Compilazione, installazione e uso: [docs/ANDROID_SETUP.md](../../docs/ANDROID_SETUP.md)
- Associazione alla regia: [docs/PAIRING.md](../../docs/PAIRING.md)
- Architettura del codice: [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=CONTROL_PLANE_URL=https://<worker>.<sottodominio>.workers.dev
```
