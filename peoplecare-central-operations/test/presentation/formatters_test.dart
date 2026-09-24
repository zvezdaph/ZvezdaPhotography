import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/presentation/shared/csv.dart';
import 'package:peoplecare_central_operations/src/presentation/shared/formatters.dart';

import '../support/test_support.dart';

void main() {
  setUpAll(initItalianFormatting);

  test('date e orari in italiano', () {
    final value = DateTime(2026, 9, 24, 8, 5);
    expect(Fmt.date(value), '24/09/2026');
    expect(Fmt.time(value), '08:05');
    expect(Fmt.dayLong(value), 'giovedì 24 settembre 2026');
    expect(Fmt.monthYear(value), 'Settembre 2026');
    expect(Fmt.timeRange(value, DateTime(2026, 9, 24, 9, 35)), '08:05–09:35');
    expect(
      Fmt.timeRange(DateTime(2026, 9, 24, 22), DateTime(2026, 9, 25, 1)),
      '22:00–25/09 01:00',
    );
    expect(Fmt.minutesOfDay(465), '07:45');
  });

  test('durate, ritardi, numeri e dimensioni', () {
    expect(Fmt.duration(const Duration(minutes: 45)), '45 min');
    expect(Fmt.duration(const Duration(minutes: 90)), '1 h 30 min');
    expect(Fmt.duration(const Duration(hours: 2)), '2 h');
    expect(Fmt.delay(Duration.zero), 'puntuale');
    expect(Fmt.delay(const Duration(minutes: 12)), '+12 min');
    expect(Fmt.delay(const Duration(minutes: -3)), '-3 min');
    expect(Fmt.integer(12500), '12.500');
    expect(Fmt.count(1, 'servizio', 'servizi'), '1 servizio');
    expect(Fmt.count(0, 'servizio', 'servizi'), '0 servizi');
    expect(Fmt.count(1200, 'servizio', 'servizi'), '1.200 servizi');
    expect(Fmt.hoursFromMinutes(750), '12,5 h');
    expect(Fmt.percent(0.764), '76%');
    expect(Fmt.percent(null), '—');
    expect(Fmt.fileSize(2 * 1024 * 1024 + 300000), '2,3 MB');
  });

  test('tempi relativi ed etichette dei giorni', () {
    final now = DateTime(2026, 9, 24, 10, 30);
    expect(
      Fmt.relative(now.subtract(const Duration(seconds: 20)), now),
      'adesso',
    );
    expect(
      Fmt.relative(now.subtract(const Duration(minutes: 17)), now),
      '17 min fa',
    );
    expect(
      Fmt.relative(now.add(const Duration(minutes: 20)), now),
      'tra 20 min',
    );
    expect(Fmt.relative(DateTime(2026, 9, 23, 19, 7), now), 'ieri 19:07');
    expect(Fmt.dayLabel(DateTime(2026, 9, 25, 8), now), 'Domani');
    expect(Fmt.dayLabel(DateTime(2026, 9, 26, 8), now), 'Sab 26 set');
  });

  test('CSV compatibile con Excel italiano', () {
    final bytes = buildCsv(
      ['Codice', 'Note'],
      [
        ['SRV-1', 'Citofono "Rossi"; secondo piano'],
        ['SRV-2', null],
      ],
    );
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(
      utf8.decode(bytes.sublist(3)),
      'Codice;Note\r\n'
      'SRV-1;"Citofono ""Rossi""; secondo piano"\r\n'
      'SRV-2;\r\n',
    );
    expect(
      timestampedFileName('servizi', DateTime(2026, 9, 4, 7, 5)),
      'servizi_20260904_0705.csv',
    );
  });
}
