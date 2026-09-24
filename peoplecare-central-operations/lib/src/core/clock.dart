/// Sorgente dell'ora corrente.
///
/// Tutta la logica che dipende da "adesso" (ritardi, servizi in corso, dati
/// demo generati attorno alla data odierna) riceve un [Clock] invece di
/// chiamare direttamente `DateTime.now()`, così test e simulazioni possono
/// controllare il tempo.
abstract interface class Clock {
  DateTime now();
}

/// Orologio di sistema (ora locale della postazione).
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Orologio fermo su un istante, spostabile manualmente (test).
class FixedClock implements Clock {
  FixedClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void set(DateTime value) => _now = value;

  void advance(Duration delta) => _now = _now.add(delta);
}
