# HANDOFF — collegare PeopleCare Central Operations al sistema PeopleCare

Guida per lo sviluppatore che sostituirà i dati DEMO con le API reali.
Leggere prima [README.md](README.md) (panoramica),
[API_CONTRACT.md](API_CONTRACT.md) (API attese) e
[DATA_MODELS.md](DATA_MODELS.md) (modelli e regole).

## 1. Stato alla consegna

| Area | Stato |
|---|---|
| Interfaccia (11 sezioni, dettaglio e form del servizio, dialoghi di azione, ricerca rapida, notifiche, tema chiaro/scuro) | Completa, legge e scrive **solo** tramite repository astratti |
| Dominio (entità, filtri, repository astratti, regole pure) | Completo — `lib/src/domain` |
| Repository DEMO in memoria + simulatore dell'app mobile | Completi — `lib/src/data/mock`, usati solo dal composition root |
| Codec JSON, corpi delle richieste, parametri di ricerca, mappatura errori, decoder SSE | Pronti e testati — `lib/src/data/dto` |
| Repository HTTP verso PeopleCare | **Da realizzare** (questa guida) |
| Autenticazione (login, token) | **Da definire** con il team PeopleCare: fuori perimetro |
| Backend, database, endpoint | **Non inclusi e non esistenti**: API_CONTRACT.md è la proposta |
| Runner Windows, script di build, pipeline CI | Pronti |

Fuori perimetro per scelta: backend, app mobile degli operatori,
PeopleCareTV, Patient Safety.

## 2. Architettura in breve

```text
lib/
  main.dart                     avvio: formattazione italiana, PeopleCareBootstrap
  src/
    core/                       orologio, errori tipizzati, paginazione, date, testo
    domain/                     entità, filtri, repository astratti, regole pure (Dart puro)
    data/
      mock/                     SOLO DEMO: backend in memoria, dati generati, simulatore
      dto/                      JSON <-> entità secondo API_CONTRACT.md (pronto per HTTP)
    platform/                   accesso ai file (finestre di dialogo di Windows)
    presentation/               tema, stato condiviso, widget, shell, schermate
    app/                        configurazione e composition root (bootstrap.dart)
```

Regole verificate da `test/architecture_test.dart`:

- il dominio non importa Flutter né altri livelli;
- l'interfaccia non importa `data/`, `app/` né il plugin dei file;
- solo `lib/src/app/bootstrap.dart` importa `data/mock`;
- i DTO dipendono solo dal dominio;
- nessuna credenziale, token, chiave o URL reale nel sorgente.

Flusso dei dati: `bootstrap.dart` crea `PeopleCareRepositories` (l'insieme
dei repository) → `AppDependencies` → `AppScope` (InheritedWidget) → ogni
schermata ha un controller (`ScreenController`) che legge dai repository e si
ricarica quando arriva un evento sugli argomenti che la riguardano.

## 3. Cosa collegare, passo per passo

### 3.1 Dipendenza HTTP

Aggiungere a `pubspec.yaml` un client HTTP (es. `http`), eventualmente un
client SSE, e il pacchetto per l'autenticazione scelto (vedi §4).

### 3.2 Client API

Creare `lib/src/data/api/api_client.dart`. Responsabilità:

- indirizzo base da `AppConfig.apiBaseUrl` (`PEOPLECARE_API_BASE_URL`);
- header `Authorization: Bearer …` da un `TokenProvider` (§4), più
  `Accept`, `X-Request-Id`, `User-Agent`, `Idempotency-Key` sulle creazioni;
- timeout di 20 secondi; nuovi tentativi solo per le `GET`;
- JSON in ingresso/uscita; errori HTTP → `exceptionFromApiError` (già
  pronto); errori di rete e timeout → `ConnectivityException`; JSON non
  valido (`FormatException`) → `UnexpectedRepositoryException`;
- su `401`: un solo tentativo di rinnovo del token, poi
  `UnauthenticatedException`.

Esempio di impostazione (da adattare, non incluso nel progetto):

```dart
abstract interface class TokenProvider {
  Future<String> accessToken();
  Future<void> invalidate();
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? client})
    : _http = client ?? http.Client();

  final Uri baseUrl;
  final TokenProvider tokens;
  final http.Client _http;

  Future<Object?> getJson(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);

  Future<Object?> sendJson(String method, String path, JsonMap body) =>
      _send(method, path, body: body);

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    JsonMap? body,
  }) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: query,
    );
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer ${await tokens.accessToken()}',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 20)),
      );
    } on TimeoutException {
      throw const ConnectivityException();
    } on http.ClientException {
      throw const ConnectivityException();
    }
    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw exceptionFromApiError(response.statusCode, decoded);
    }
    return decoded;
  }

  Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
```

### 3.3 Repository HTTP

Creare `lib/src/data/api/api_repositories.dart` con un'implementazione per
ogni interfaccia di `lib/src/domain/repositories`. La tabella metodo →
endpoint è in API_CONTRACT §3; per ogni chiamata esistono già i codec:

| Serve | Funzione pronta |
|---|---|
| Leggere entità | `serviceFromJson`, `operatorFromJson`, `facilityFromJson`, `serviceTypeFromJson`, `patientFromJson`, `changeRequestFromJson`, `documentFromJson`, `notificationFromJson`, `auditEntryFromJson`, `operationalReportFromJson`, `centralUserFromJson`, `pagedResultFromJson` |
| Corpi di creazione/modifica | `serviceDraftToJson`, `operatorDraftToJson`, `facilityDraftToJson`, `serviceTypeDraftToJson` (con `expectedVersion` per le `PUT`) |
| Corpi delle azioni | `rescheduleRequestToJson`, `reassignRequestToJson`, `reasonRequestToJson`, `operatorStatusRequestToJson`, `linkAccountRequestToJson`, `replyRequestToJson`, `changeRequestResolutionToJson`, `expectedVersionParams` |
| Parametri di ricerca | `serviceQueryParams`, `calendarParams`, `operatorQueryParams`, `changeRequestQueryParams`, `documentQueryParams`, `notificationQueryParams`, `auditQueryParams`, `reportQueryParams` |
| Caricamento documenti | `documentUploadFields` (campi della richiesta multipart; il file va nella parte `file`) |
| Errori | `exceptionFromApiError` |
| Eventi | `SseDecoder`, `liveMessageFromSse` |

Esempio per il servizio (stesso schema per gli altri):

```dart
class ApiServiceRepository implements ServiceRepository {
  ApiServiceRepository(this._api);

  final ApiClient _api;

  JsonMap _map(Object? json) => (json! as Map).cast<String, Object?>();

  @override
  Future<PagedResult<Service>> searchServices(
    ServiceQuery query, {
    PageRequest page = const PageRequest(),
  }) async => pagedResultFromJson(
    _map(await _api.getJson('/services', serviceQueryParams(query, page))),
    serviceFromJson,
  );

  @override
  Future<Service> rescheduleService(
    String id, {
    required DateTime start,
    required DateTime end,
    String? reason,
    required int expectedVersion,
  }) async => serviceFromJson(
    _map(
      await _api.sendJson(
        'POST',
        '/services/$id/reschedule',
        rescheduleRequestToJson(
          start: start,
          end: end,
          reason: reason,
          expectedVersion: expectedVersion,
        ),
      ),
    ),
  );

  // ... gli altri metodi allo stesso modo.
}
```

Note:

- `listServicesInRange` usa `GET /services/calendar` e non è paginato;
  l'interfaccia chiede al massimo 31 giorni per volta.
- `listQualifications`, `countUnread`, `markRead`, `markAllRead` hanno
  risposte semplici (`{"items": [...]}`, `{"count": n}`, `204`).
- `downloadDocument` legge i byte e ricava il nome del file da
  `Content-Disposition`.
- Le esportazioni CSV leggono tutte le pagine con `fetchAllPages`
  (`lib/src/core/paging.dart`): il server può limitare `page_size`.

### 3.4 Eventi in tempo reale

`OperationalEventsRepository.watchEvents()` e
`NotificationRepository.watchNew()` devono essere stream **broadcast**,
alimentati da un'unica connessione a `GET /events`:

1. aprire la connessione con `Accept: text/event-stream` e il token;
2. trasformare le righe con `const SseDecoder()` e ogni messaggio con
   `liveMessageFromSse`: `LiveOperationalEvent` → stream degli eventi,
   `LiveNotification` → stream delle notifiche;
3. alla caduta, riconnettersi con attesa crescente (1 s, 2 s, 5 s, 10 s,
   poi ogni 30 s) inviando `Last-Event-ID`;
4. dopo una riconnessione emettere un evento per ogni argomento, così le
   schermate aperte si riallineano;
5. chiudere tutto in `onDispose` di `PeopleCareRepositories`.

Se il sistema non offre il canale, un'alternativa accettabile è un
aggiornamento periodico (es. ogni 30–60 s) che emetta eventi `servizi`,
`richieste_modifica`, `documenti`, `notifiche` e confronti le notifiche non
lette per alimentare `watchNew()`.

### 3.5 Composition root

In `lib/src/app/bootstrap.dart` il ramo `DataSourceKind.api` oggi lancia
`DataSourceNotAvailableException`. Sostituirlo con la costruzione dei
repository HTTP:

```dart
DataSourceKind.api => createApiRepositories(
  baseUrl: config.apiBaseUrl ??
      (throw const DataSourceNotAvailableException(
        'Indirizzo delle API non configurato (PEOPLECARE_API_BASE_URL).',
      )),
  tokens: tokenProvider,
),
```

`createApiRepositories` restituisce `PeopleCareRepositories` con
`DataSourceInfo(name: 'PeopleCare', isDemo: false)`: la barra "MODALITÀ DEMO"
e il badge "Dati DEMO" spariscono automaticamente. Nessun'altra parte
dell'interfaccia va toccata.

### 3.6 Build

```powershell
.\scripts\build_windows.ps1 -DataSource api -ApiBaseUrl https://<host>/central-operations/v1
```

equivale a `flutter build windows --release
--dart-define=PEOPLECARE_DATA_SOURCE=api
--dart-define=PEOPLECARE_API_BASE_URL=…`. L'indirizzo non è un segreto;
**token e credenziali non vanno mai passati come `--dart-define`** (finirebbero
nell'eseguibile).

## 4. Autenticazione (da concordare)

Il client non contiene né gestisce credenziali. Proposta per un'app desktop:

- OpenID Connect / OAuth 2.0 con *authorization code + PKCE* aperto nel
  browser di sistema e redirect su loopback (`http://127.0.0.1:<porta>`,
  RFC 8252); client pubblico, **senza client secret**;
- token conservati solo nell'archivio protetto dell'utente Windows
  (Credential Manager / DPAPI), mai in chiaro su disco né nei log;
- `TokenProvider` rinnova l'access token con il refresh token e, se non è
  possibile, riporta alla schermata di accesso;
- `GET /me` fornisce nome, ruolo e strutture di competenza mostrati nella
  barra laterale.

La schermata di accesso non è inclusa: va aggiunta in `PeopleCareBootstrap`
(`lib/src/app/app.dart`) prima di `createAppDependencies`.

## 5. Cosa fa oggi il mock e dovrà fare il sistema

Il backend demo (`lib/src/data/mock/mock_backend.dart`) imita il sistema per
rendere l'interfaccia realistica. Con le API reali queste responsabilità
passano al sistema PeopleCare:

| Responsabilità | Nel mock | Nel sistema reale |
|---|---|---|
| Codici `OP-`, `SRV-`, `RM-`, `STR-`, `TS-` | Contatori in memoria | Generati dal sistema |
| Validazione e regole di stato | `_validate…`, `ServicePolicy` | Obbligatorie lato server (API_CONTRACT §9) |
| `version` e conflitti | `checkVersion` | `409 version_conflict` |
| Contatori `document_count`, `open_change_request_count` | `refreshServiceCounters` | Calcolati dal sistema |
| Registro attività | `audit(...)` a ogni operazione | Scritto dal sistema, in sola aggiunta |
| Notifiche (inizio/fine, richieste, documenti, ritardi) | `notify(...)` e simulatore | Generate dal sistema |
| Eventi in tempo reale | `StreamController` in memoria | `GET /events` |
| Avvii, chiusure, richieste e documenti degli operatori | `LiveActivitySimulator` (ogni 15 s) | App mobile degli operatori |
| Report | `ReportCalculator` sui dati in memoria | `GET /reports/operational` (o lo stesso calcolo sui servizi del periodo) |
| Contenuto dei documenti | PDF dimostrativi generati | File reali |

Quando il ramo `api` è attivo **nessun** file di `data/mock` viene usato; la
cartella può restare per le demo e per i test.

## 6. Test

```bash
flutter test            # tutta la suite
scripts/check.sh        # formattazione, analisi, test (come la CI)
```

| Cartella | Contenuto |
|---|---|
| `test/domain` | Regole pure: politiche di stato, sovrapposizioni, anomalie, suggerimenti, report, date, paginazione |
| `test/data` | Dati demo, repository demo, simulatore, codec JSON, **contratto API** (fixture ed esempi di API_CONTRACT.md) |
| `test/presentation` | Avvio completo dell'app su 1920×1080, navigazione, scorciatoie, form del nuovo servizio, calendario, formattazione, CSV |
| `test/architecture_test.dart` | Dipendenze tra livelli, assenza di credenziali e URL reali |
| `test/fixtures/api` | Esempi JSON del contratto, riusabili per i test dei repository HTTP |

Per i repository HTTP si consiglia un client finto (es. `MockClient` di
`package:http/testing`) che risponda con i file di `test/fixtures/api` e
verifichi metodo, percorso, parametri e corpo di ogni chiamata.
`test/support/test_support.dart` mostra come avviare l'app completa nei test
con un orologio fisso.

## 7. Distribuzione su Windows

- Requisiti di build: Windows 10/11 x64, Flutter 3.47.5 (canale stable),
  Visual Studio 2022 con il carico di lavoro "Sviluppo di applicazioni
  desktop con C++".
- `scripts\build_windows.ps1` produce
  `build\windows\x64\runner\Release\PeopleCareCentralOperations.exe` e lo ZIP
  in `dist\`. Va distribuita l'intera cartella `Release` (eseguibile, DLL,
  cartella `data`).
- Sulle postazioni serve il Microsoft Visual C++ Redistributable 2015–2022
  (x64), normalmente già presente; in caso contrario installarlo o includere
  `msvcp140.dll`, `vcruntime140.dll` e `vcruntime140_1.dll` accanto
  all'eseguibile.
- Passi successivi consigliati: firma digitale dell'eseguibile e pacchetto
  MSIX o installer aziendale.
- La finestra si apre centrata a 1600×940 (massimizzata sugli schermi più
  piccoli), con dimensione minima 1280×720; titolo, icona e informazioni di
  versione sono in `windows/runner` (l'icona si rigenera con
  `scripts/generate_app_icon.py`).

## 8. Limiti noti e prossimi passi

- Preferenze dell'utente (tema, barra laterale compressa, avvisi a comparsa)
  non salvate tra un avvio e l'altro.
- Nessuna modalità offline: senza sistema raggiungibile le schermate mostrano
  l'errore e il pulsante "Riprova".
- Interfaccia solo in italiano; formati italiani fissi (`it_IT`).
- Il calendario disegna tutti i servizi del giorno o della settimana
  visualizzati: adeguato a qualche centinaio di servizi al giorno.
- Il rilevamento di sovrapposizioni e anomalie avviene nel client sui dati
  caricati; il sistema può fornire le stesse informazioni se preferibile.

## 9. Checklist per il collegamento

- [ ] Contratto API confermato o adeguato con il team PeopleCare
      (aggiornare API_CONTRACT.md e le fixture insieme: il test verifica che
      coincidano).
- [ ] Autenticazione definita; `TokenProvider` e schermata di accesso
      realizzati.
- [ ] `lib/src/data/api/` con client, repository ed eventi; test con client
      finto sulle fixture.
- [ ] Ramo `DataSourceKind.api` in `bootstrap.dart`.
- [ ] Build `-DataSource api` provata su una postazione della Centrale.
- [ ] Verificato che la barra "MODALITÀ DEMO" non compaia con i dati reali.
- [ ] `scripts/check.sh` e pipeline CI verdi.
