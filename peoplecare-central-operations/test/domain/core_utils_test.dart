import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/core/text.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

void main() {
  group('PagedResult', () {
    test('fromAll taglia la pagina e calcola gli indici', () {
      final all = List.generate(125, (i) => i);
      final page = PagedResult.fromAll(all, const PageRequest(page: 3));
      expect(page.items.first, 100);
      expect(page.items, hasLength(25));
      expect(page.total, 125);
      expect(page.pageCount, 3);
      expect(page.hasNext, isFalse);
      expect(page.hasPrevious, isTrue);
      expect(page.firstIndex, 101);
      expect(page.lastIndex, 125);
    });

    test('pagina oltre la fine e lista vuota', () {
      final beyond = PagedResult.fromAll([1, 2], const PageRequest(page: 5));
      expect(beyond.items, isEmpty);
      final empty = PagedResult.fromAll(<int>[], const PageRequest());
      expect(empty.pageCount, 1);
      expect(empty.firstIndex, 0);
      expect(empty.lastIndex, 0);
    });
  });

  group('fetchAllPages', () {
    test('legge tutte le pagine fino al totale', () async {
      final all = List.generate(1234, (i) => i);
      final requested = <int>[];
      final items = await fetchAllPages((page) async {
        requested.add(page.page);
        return PagedResult.fromAll(all, page);
      });
      expect(items, all);
      expect(requested, [1, 2, 3]);
    });

    test('si ferma al limite e con pagine vuote', () async {
      final all = List.generate(2000, (i) => i);
      final limited = await fetchAllPages(
        (page) async => PagedResult.fromAll(all, page),
        pageSize: 300,
        maxItems: 700,
      );
      expect(limited, hasLength(700));
      final empty = await fetchAllPages(
        (page) async => PagedResult.fromAll(<int>[], page),
      );
      expect(empty, isEmpty);
    });
  });

  group('ricerca testuale', () {
    test('ignora maiuscole, accenti e ordine delle parole', () {
      expect(normalizeForSearch('  Niccolò   FERRÀ '), 'niccolo ferra');
      expect(matchesSearch('ferra nicco', ['Niccolò', 'Ferrà']), isTrue);
      expect(matchesSearch('rossi', ['Niccolò', null, 'Ferrà']), isFalse);
      expect(matchesSearch('   ', ['qualsiasi']), isTrue);
    });

    test('emptyToNull', () {
      expect(emptyToNull(null), isNull);
      expect(emptyToNull('   '), isNull);
      expect(emptyToNull('  testo '), 'testo');
    });
  });

  group('errori dei repository', () {
    test('describeError restituisce il messaggio leggibile', () {
      expect(
        describeError(const OperationNotAllowedException('Non consentito.')),
        'Non consentito.',
      );
      expect(
        describeError(const ConcurrencyConflictException()),
        contains('modificato'),
      );
      expect(
        describeError(StateError('interno')),
        'Si è verificato un errore imprevisto.',
      );
    });
  });
}
