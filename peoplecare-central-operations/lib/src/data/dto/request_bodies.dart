import '../../domain/domain.dart';
import 'json_reader.dart';

/// Corpi delle richieste di azione previste da API_CONTRACT.md.
///
/// Ogni modifica porta `expected_version` (concorrenza ottimistica): il
/// sistema risponde `409 version_conflict` se la risorsa è cambiata.

/// `POST /services/{id}/reschedule`
JsonMap rescheduleRequestToJson({
  required DateTime start,
  required DateTime end,
  String? reason,
  required int expectedVersion,
}) => {
  'scheduled_start': formatTimestamp(start),
  'scheduled_end': formatTimestamp(end),
  'reason': reason,
  'expected_version': expectedVersion,
};

/// `POST /services/{id}/reassign`; `operator_id: null` rimuove l'assegnazione.
JsonMap reassignRequestToJson({
  required String? operatorId,
  String? reason,
  required int expectedVersion,
}) => {
  'operator_id': operatorId,
  'reason': reason,
  'expected_version': expectedVersion,
};

/// `POST /services/{id}/cancel` e `POST /services/{id}/mark-to-reschedule`.
JsonMap reasonRequestToJson({
  required String reason,
  required int expectedVersion,
}) => {'reason': reason, 'expected_version': expectedVersion};

/// `POST /operators/{id}/status`
JsonMap operatorStatusRequestToJson({
  required OperatorStatus status,
  String? reason,
  required int expectedVersion,
}) => {
  'status': status.code,
  'reason': reason,
  'expected_version': expectedVersion,
};

/// `POST /operators/{id}/account`
JsonMap linkAccountRequestToJson({
  required String username,
  required int expectedVersion,
}) => {'username': username, 'expected_version': expectedVersion};

/// `POST /change-requests/{id}/reply`
JsonMap replyRequestToJson({
  required String message,
  required int expectedVersion,
}) => {'message': message, 'expected_version': expectedVersion};

/// Parametro di query per le `DELETE` soggette a controllo di versione.
Map<String, String> expectedVersionParams(int expectedVersion) => {
  'expected_version': '$expectedVersion',
};
