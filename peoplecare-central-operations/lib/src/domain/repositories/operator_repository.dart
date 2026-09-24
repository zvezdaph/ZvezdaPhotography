import '../entities/operator.dart';
import '../queries/queries.dart';

/// Anagrafica degli operatori PeopleCare.
///
/// Il codice operatore (`OP-000184`) è assegnato dal sistema alla creazione.
/// Le modifiche richiedono la `version` letta, per evitare di sovrascrivere
/// modifiche altrui.
abstract interface class OperatorRepository {
  Future<List<Operator>> listOperators([
    OperatorQuery query = const OperatorQuery(),
  ]);

  Future<Operator> getOperator(String id);

  /// Qualifiche/ruoli ammessi dal sistema.
  Future<List<String>> listQualifications();

  Future<Operator> createOperator(OperatorDraft draft);

  Future<Operator> updateOperator(
    String id,
    OperatorDraft draft, {
    required int expectedVersion,
  });

  /// Attiva, sospende o disabilita l'operatore.
  Future<Operator> changeStatus(
    String id,
    OperatorStatus status, {
    String? reason,
    required int expectedVersion,
  });

  /// Collega l'operatore a un account PeopleCare esistente o da invitare.
  Future<Operator> linkAccount(
    String id, {
    required String username,
    required int expectedVersion,
  });

  Future<Operator> unlinkAccount(String id, {required int expectedVersion});
}
