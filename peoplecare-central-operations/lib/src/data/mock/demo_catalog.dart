// Anagrafiche DEMO: nomi, indirizzi e contatti sono inventati.
//
// Le email usano il dominio riservato `.example` (RFC 2606) e i numeri di
// telefono hanno un blocco centrale "000", così nessun dato può coincidere con
// contatti reali.

/// Utente della Centrale mostrato nella sessione demo.
const demoCentralUser = (
  id: 'usr-demo-001',
  name: 'Laura Bianchi',
  role: 'Operatrice di centrale',
);

/// Altri utenti della Centrale che compaiono nello storico demo.
const demoCentralColleagues = ['Davide Rota', 'Marta Pellegrini'];

const demoQualifications = [
  'OSS',
  'Infermiere',
  'Fisioterapista',
  'Educatore professionale',
  'ASA',
  'Assistente sociale',
];

typedef DemoFacility = ({
  String code,
  String name,
  String kind,
  String address,
  String city,
  String phone,
  List<String> areaCities,
});

const demoFacilities = <DemoFacility>[
  (
    code: 'STR-01',
    name: 'RSA Il Glicine',
    kind: 'rsa',
    address: 'Via dei Glicini 12',
    city: 'Bergamo',
    phone: '+39 035 000 1201',
    areaCities: ['Bergamo'],
  ),
  (
    code: 'STR-02',
    name: 'Centro Diurno Arcobaleno',
    kind: 'centro_diurno',
    address: 'Via Roma 45',
    city: 'Seriate',
    phone: '+39 035 000 1202',
    areaCities: ['Seriate'],
  ),
  (
    code: 'STR-03',
    name: 'Servizio Domiciliare Bergamo Nord',
    kind: 'servizio_domiciliare',
    address: 'Via Carducci 8',
    city: 'Bergamo',
    phone: '+39 035 000 1203',
    areaCities: ['Bergamo', 'Ponteranica', 'Sorisole', 'Almè', 'Villa d\'Almè'],
  ),
  (
    code: 'STR-04',
    name: 'Servizio Domiciliare Valle Seriana',
    kind: 'servizio_domiciliare',
    address: 'Piazza Garibaldi 3',
    city: 'Alzano Lombardo',
    phone: '+39 035 000 1204',
    areaCities: ['Alzano Lombardo', 'Nembro', 'Albino', 'Ranica', 'Pradalunga'],
  ),
  (
    code: 'STR-05',
    name: 'Comunità Alloggio Le Querce',
    kind: 'comunita_alloggio',
    address: 'Via delle Querce 21',
    city: 'Treviolo',
    phone: '+39 035 000 1205',
    areaCities: ['Treviolo'],
  ),
];

typedef DemoServiceType = ({
  String code,
  String name,
  String category,
  int minutes,
  List<String> qualifications,
  String description,
  bool active,
});

const demoServiceTypes = <DemoServiceType>[
  (
    code: 'TS-01',
    name: 'Igiene personale',
    category: 'Assistenza di base',
    minutes: 60,
    qualifications: ['OSS', 'ASA'],
    description: 'Igiene completa o parziale, cura della persona e vestizione.',
    active: true,
  ),
  (
    code: 'TS-02',
    name: 'Aiuto nell\'alimentazione',
    category: 'Assistenza di base',
    minutes: 45,
    qualifications: ['OSS', 'ASA'],
    description: 'Preparazione e assistenza durante il pasto.',
    active: true,
  ),
  (
    code: 'TS-03',
    name: 'Mobilizzazione e deambulazione',
    category: 'Assistenza di base',
    minutes: 45,
    qualifications: ['OSS', 'Fisioterapista'],
    description:
        'Mobilizzazione, trasferimenti letto-carrozzina, cammino assistito.',
    active: true,
  ),
  (
    code: 'TS-04',
    name: 'Somministrazione terapia',
    category: 'Sanitaria',
    minutes: 30,
    qualifications: ['Infermiere'],
    description:
        'Somministrazione della terapia prescritta e verifica aderenza.',
    active: true,
  ),
  (
    code: 'TS-05',
    name: 'Medicazione',
    category: 'Sanitaria',
    minutes: 30,
    qualifications: ['Infermiere'],
    description: 'Medicazione semplice o avanzata di lesioni.',
    active: true,
  ),
  (
    code: 'TS-06',
    name: 'Prelievo ematico domiciliare',
    category: 'Sanitaria',
    minutes: 20,
    qualifications: ['Infermiere'],
    description: 'Prelievo a domicilio e consegna dei campioni al laboratorio.',
    active: true,
  ),
  (
    code: 'TS-07',
    name: 'Monitoraggio parametri vitali',
    category: 'Sanitaria',
    minutes: 30,
    qualifications: ['Infermiere', 'OSS'],
    description: 'Pressione, frequenza, saturazione, glicemia e registrazione.',
    active: true,
  ),
  (
    code: 'TS-08',
    name: 'Fisioterapia domiciliare',
    category: 'Riabilitativa',
    minutes: 60,
    qualifications: ['Fisioterapista'],
    description: 'Seduta riabilitativa secondo il piano del fisiatra.',
    active: true,
  ),
  (
    code: 'TS-09',
    name: 'Supporto educativo',
    category: 'Educativa',
    minutes: 90,
    qualifications: ['Educatore professionale'],
    description: 'Attività educative e di socializzazione.',
    active: true,
  ),
  (
    code: 'TS-10',
    name: 'Accompagnamento a visita',
    category: 'Sociale',
    minutes: 120,
    qualifications: ['OSS', 'ASA'],
    description: 'Accompagnamento a visite mediche ed esami.',
    active: true,
  ),
  (
    code: 'TS-11',
    name: 'Compagnia e sollievo',
    category: 'Sociale',
    minutes: 90,
    qualifications: [],
    description: 'Presenza di sollievo per il caregiver familiare.',
    active: true,
  ),
  (
    code: 'TS-12',
    name: 'Colloquio sociale',
    category: 'Sociale',
    minutes: 60,
    qualifications: ['Assistente sociale'],
    description: 'Colloquio di valutazione e aggiornamento del progetto.',
    active: true,
  ),
  (
    code: 'TS-13',
    name: 'Verifica apparato telesoccorso',
    category: 'Sociale',
    minutes: 30,
    qualifications: [],
    description: 'Servizio sostituito dal controllo remoto: non più erogato.',
    active: false,
  ),
];

typedef DemoOperator = ({
  int number,
  String firstName,
  String lastName,
  String qualification,
  int facility,
  List<int> secondary,
  String status,
  String? statusReason,
  String? account,
  String shift,
});

/// Operatori demo. `facility`/`secondary` sono indici in [demoFacilities];
/// `account`: `attivo`, `invitato`, `bloccato` oppure `null` (nessun account);
/// `shift`: `mattina`, `pomeriggio` o `spezzato`.
const demoOperators = <DemoOperator>[
  (
    number: 161,
    firstName: 'Giulia',
    lastName: 'Ferrari',
    qualification: 'OSS',
    facility: 2,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 162,
    firstName: 'Marco',
    lastName: 'Colombo',
    qualification: 'Infermiere',
    facility: 2,
    secondary: [3],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'spezzato',
  ),
  (
    number: 163,
    firstName: 'Sara',
    lastName: 'Ricci',
    qualification: 'OSS',
    facility: 2,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'pomeriggio',
  ),
  (
    number: 164,
    firstName: 'Luca',
    lastName: 'Marino',
    qualification: 'Fisioterapista',
    facility: 2,
    secondary: [3, 0],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 165,
    firstName: 'Chiara',
    lastName: 'Greco',
    qualification: 'Infermiere',
    facility: 2,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 166,
    firstName: 'Andrea',
    lastName: 'Bruno',
    qualification: 'OSS',
    facility: 2,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'invitato',
    shift: 'pomeriggio',
  ),
  (
    number: 167,
    firstName: 'Francesca',
    lastName: 'Gallo',
    qualification: 'ASA',
    facility: 2,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 168,
    firstName: 'Matteo',
    lastName: 'Conti',
    qualification: 'Educatore professionale',
    facility: 1,
    secondary: [2],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'pomeriggio',
  ),
  (
    number: 169,
    firstName: 'Elena',
    lastName: 'De Luca',
    qualification: 'Infermiere',
    facility: 3,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 170,
    firstName: 'Davide',
    lastName: 'Costa',
    qualification: 'OSS',
    facility: 3,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 171,
    firstName: 'Alessia',
    lastName: 'Giordano',
    qualification: 'OSS',
    facility: 3,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'pomeriggio',
  ),
  (
    number: 172,
    firstName: 'Simone',
    lastName: 'Mancini',
    qualification: 'ASA',
    facility: 3,
    secondary: [],
    status: 'sospeso',
    statusReason: 'Congedo per motivi familiari fino a fine mese',
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 173,
    firstName: 'Martina',
    lastName: 'Rizzo',
    qualification: 'Fisioterapista',
    facility: 3,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'pomeriggio',
  ),
  (
    number: 174,
    firstName: 'Federico',
    lastName: 'Lombardi',
    qualification: 'Infermiere',
    facility: 3,
    secondary: [2],
    status: 'attivo',
    statusReason: null,
    account: 'bloccato',
    shift: 'spezzato',
  ),
  (
    number: 175,
    firstName: 'Valentina',
    lastName: 'Moretti',
    qualification: 'OSS',
    facility: 0,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 176,
    firstName: 'Stefano',
    lastName: 'Barbieri',
    qualification: 'Educatore professionale',
    facility: 0,
    secondary: [4],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'pomeriggio',
  ),
  (
    number: 177,
    firstName: 'Paola',
    lastName: 'Fontana',
    qualification: 'Assistente sociale',
    facility: 0,
    secondary: [2, 3],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 178,
    firstName: 'Roberto',
    lastName: 'Santoro',
    qualification: 'OSS',
    facility: 0,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: null,
    shift: 'pomeriggio',
  ),
  (
    number: 179,
    firstName: 'Anna',
    lastName: 'Mariani',
    qualification: 'Infermiere',
    facility: 0,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 180,
    firstName: 'Giorgio',
    lastName: 'Rinaldi',
    qualification: 'ASA',
    facility: 0,
    secondary: [],
    status: 'disabilitato',
    statusReason: 'Cessato rapporto di collaborazione',
    account: null,
    shift: 'mattina',
  ),
  (
    number: 181,
    firstName: 'Silvia',
    lastName: 'Caruso',
    qualification: 'OSS',
    facility: 1,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 182,
    firstName: 'Nicola',
    lastName: 'Ferrara',
    qualification: 'Infermiere',
    facility: 1,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 183,
    firstName: 'Irene',
    lastName: 'Martini',
    qualification: 'OSS',
    facility: 4,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'pomeriggio',
  ),
  (
    number: 184,
    firstName: 'Paolo',
    lastName: 'Leone',
    qualification: 'OSS',
    facility: 4,
    secondary: [0],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'mattina',
  ),
  (
    number: 185,
    firstName: 'Beatrice',
    lastName: 'Longo',
    qualification: 'Educatore professionale',
    facility: 4,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: null,
    shift: 'pomeriggio',
  ),
  (
    number: 186,
    firstName: 'Tommaso',
    lastName: 'Gentile',
    qualification: 'Infermiere',
    facility: 3,
    secondary: [],
    status: 'attivo',
    statusReason: null,
    account: 'attivo',
    shift: 'pomeriggio',
  ),
];

const demoPatientFirstNames = [
  'Maria', 'Giuseppe', 'Anna', 'Giovanni', 'Rosa', 'Antonio', 'Angela', //
  'Francesco', 'Giuseppina', 'Luigi', 'Teresa', 'Salvatore', 'Lucia', //
  'Mario', 'Carmela', 'Vincenzo', 'Franca', 'Pietro', 'Luisa', 'Bruno', //
  'Rita', 'Carlo', 'Adriana', 'Sergio', 'Gabriella', 'Renato', 'Liliana', //
  'Franco', 'Silvana', 'Aldo', 'Ida', 'Ettore', 'Nella', 'Dino', 'Wanda', //
  'Gino', 'Elsa', 'Aurelio', 'Iolanda', 'Tullio', 'Bianca', 'Nando', //
  'Graziella', 'Osvaldo', 'Ornella', 'Livio', 'Marisa', 'Remo',
];

const demoPatientLastNames = [
  'Rossi', 'Russo', 'Esposito', 'Romano', 'Villa', 'Ricciardi', 'Marchi', //
  'Pagani', 'Bonetti', 'Galbiati', 'Cattaneo', 'Mazza', 'Sala', 'Brambilla', //
  'Pozzi', 'Testa', 'Rota', 'Locatelli', 'Pesenti', 'Carminati', 'Belotti', //
  'Gamba', 'Zanchi', 'Epis', 'Cortinovis', 'Ghisalberti', 'Previtali', //
  'Arnoldi', 'Bonomi', 'Moioli', 'Bergamelli', 'Ravasio', 'Personeni', //
  'Carrara', 'Lazzari', 'Rottoli', 'Nava', 'Suardi', 'Pezzotta', 'Mologni', //
  'Tiraboschi', 'Maffeis', 'Bettoni', 'Agazzi', 'Signori', 'Lorenzi', //
  'Morotti', 'Viscardi',
];

const demoStreets = [
  'Via Garibaldi', 'Via Mazzini', 'Via Verdi', 'Via XX Settembre', //
  'Via San Giovanni Bosco', 'Via Leopardi', 'Via Manzoni', 'Via Dante', //
  'Via Papa Giovanni XXIII', 'Viale Vittorio Emanuele', 'Via Tasso', //
  'Via Pascoli', 'Via dei Mille', 'Via Cavour', 'Via Kennedy', 'Via Fiume', //
  'Via Trento', 'Via Trieste', 'Via Montello', 'Via Piave', 'Via Donizetti', //
  'Via Moroni', 'Via Borgo Palazzo', 'Via Corridoni',
];

const demoDirections = [
  'Citofono al cognome, 2° piano senza ascensore.',
  'Chiavi presso la vicina all\'interno 4.',
  'Cancello verde, parcheggio nel cortile interno.',
  'Cane in giardino: suonare e attendere il familiare.',
  'Scala B, interno 7. Portineria aperta 8-12.',
  'Ingresso dal retro, porta a vetri.',
  'Casa singola in fondo alla strada sterrata.',
  'Campanello non funzionante: telefonare all\'arrivo.',
];

const demoPatientNotes = [
  'Lieve ipoacusia: parlare lentamente e di fronte.',
  'Diabetico insulino-dipendente.',
  'Figlia presente il martedì e il giovedì.',
  'Allergia al lattice: usare guanti in nitrile.',
  'Deambulazione con deambulatore.',
  'Vive solo, riferimento il nipote.',
];

const demoServiceNotes = [
  'Portare kit medicazione avanzata.',
  'Verificare scorte di presidi per incontinenza.',
  'Aggiornare la scheda parametri sul diario.',
  'Il familiare chiede un contatto telefonico a fine servizio.',
  'Controllare la terapia settimanale nel dispenser.',
];

const demoCancellationReasons = [
  'Annullato su richiesta della famiglia',
  'Paziente ricoverato',
  'Sospensione temporanea del piano assistenziale',
];

const demoNotExecutedReasons = [
  'Paziente assente al domicilio',
  'Rifiuto della prestazione da parte del paziente',
  'Paziente trasferito in pronto soccorso',
];
