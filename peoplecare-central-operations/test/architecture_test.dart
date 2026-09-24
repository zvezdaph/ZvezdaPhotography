import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regole di architettura verificate sul codice sorgente.
///
/// - il dominio è Dart puro (niente Flutter, niente dati né interfaccia);
/// - l'interfaccia vede solo astrazioni: nessun import del mock o dei DTO;
/// - solo il composition root (`lib/src/app/bootstrap.dart`) conosce il mock;
/// - nessuna credenziale, token o indirizzo reale nel codice.
void main() {
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String rel(File file) => file.path.replaceAll('\\', '/');

  List<String> importsOf(File file) => [
    for (final match in RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    ).allMatches(file.readAsStringSync()))
      match.group(1)!,
  ];

  /// Percorso normalizzato di un import relativo o `package:`.
  String resolve(File from, String uri) {
    if (uri.startsWith('package:peoplecare_central_operations/')) {
      return 'lib/${uri.substring('package:peoplecare_central_operations/'.length)}';
    }
    if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
    final segments = rel(from).split('/')..removeLast();
    for (final part in uri.split('/')) {
      if (part == '..') {
        segments.removeLast();
      } else if (part != '.') {
        segments.add(part);
      }
    }
    return segments.join('/');
  }

  Map<String, List<String>> violations(
    bool Function(String path) inScope,
    bool Function(String target) forbidden,
  ) => {
    for (final file in sources)
      if (inScope(rel(file)))
        rel(file): [
          for (final uri in importsOf(file))
            if (forbidden(resolve(file, uri))) uri,
        ],
  }..removeWhere((_, list) => list.isEmpty);

  test('il sorgente è organizzato nei livelli previsti', () {
    for (final layer in [
      'lib/src/core',
      'lib/src/domain',
      'lib/src/data/mock',
      'lib/src/data/dto',
      'lib/src/platform',
      'lib/src/presentation',
      'lib/src/app',
    ]) {
      expect(Directory(layer).existsSync(), isTrue, reason: layer);
    }
  });

  test(
    'il dominio non dipende da Flutter, dati, piattaforma o interfaccia',
    () {
      expect(
        violations(
          (p) =>
              p.startsWith('lib/src/domain/') || p.startsWith('lib/src/core/'),
          (t) =>
              t.startsWith('package:flutter') ||
              t.startsWith('lib/src/data/') ||
              t.startsWith('lib/src/platform/') ||
              t.startsWith('lib/src/presentation/') ||
              t.startsWith('lib/src/app/'),
        ),
        isEmpty,
      );
    },
  );

  test('l\'interfaccia non conosce implementazioni dei dati', () {
    expect(
      violations(
        (p) => p.startsWith('lib/src/presentation/'),
        (t) =>
            t.startsWith('lib/src/data/') ||
            t.startsWith('lib/src/app/') ||
            t == 'lib/src/platform/file_selector_service.dart' ||
            t.startsWith('package:file_selector'),
      ),
      isEmpty,
    );
  });

  test('solo il composition root importa il mock', () {
    expect(
      violations(
        (p) =>
            !p.startsWith('lib/src/data/mock/') &&
            p != 'lib/src/app/bootstrap.dart',
        (t) => t.startsWith('lib/src/data/mock/'),
      ),
      isEmpty,
    );
  });

  test('i DTO dipendono solo dal dominio', () {
    expect(
      violations(
        (p) => p.startsWith('lib/src/data/dto/'),
        (t) =>
            t.startsWith('package:flutter') ||
            t.startsWith('lib/src/data/mock/') ||
            t.startsWith('lib/src/presentation/') ||
            t.startsWith('lib/src/app/'),
      ),
      isEmpty,
    );
  });

  test('nessuna credenziale, token o endpoint reale nel codice', () {
    final patterns = <String, RegExp>{
      'credenziale letterale': RegExp(
        r'''(password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*['"][^'"]{4,}['"]''',
        caseSensitive: false,
      ),
      'bearer token': RegExp(r'Bearer\s+[A-Za-z0-9\-_.=]{12,}'),
      'chiave privata': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
      'JWT': RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'),
      'URL http(s)': RegExp(r'''https?://(?!(www\.)?example\.)[^\s'"]+'''),
    };
    final found = <String>[];
    for (final file in sources) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final MapEntry(key: kind, value: pattern) in patterns.entries) {
          if (pattern.hasMatch(lines[i])) {
            found.add('${rel(file)}:${i + 1} ($kind)');
          }
        }
      }
    }
    expect(found, isEmpty);
  });

  test('le email dei dati demo usano solo domini riservati', () {
    final email = RegExp(r'[\w.+-]+@([\w-]+\.)+[\w-]+');
    final found = <String>[];
    for (final file in sources) {
      for (final match in email.allMatches(file.readAsStringSync())) {
        final address = match.group(0)!;
        if (!RegExp(r'\.example$|\.test$|\.invalid$').hasMatch(address)) {
          found.add('${rel(file)}: $address');
        }
      }
    }
    expect(found, isEmpty);
  });
}
