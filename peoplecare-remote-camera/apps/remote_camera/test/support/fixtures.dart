import 'dart:convert';
import 'dart:io';

/// Golden protocol messages shared with the Worker tests (docs/protocol-fixtures).
Map<String, Object?> fixture(String name) {
  final file = File('../../docs/protocol-fixtures/$name');
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

List<Object?> fixtureList(String name) {
  final file = File('../../docs/protocol-fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as List<Object?>;
}
