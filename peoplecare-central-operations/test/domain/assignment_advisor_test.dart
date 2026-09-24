import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

void main() {
  const advisor = AssignmentAdvisor();
  final day = DateTime(2026, 9, 25);
  final slot = DateRange(atTime(day, 10, 0), atTime(day, 11, 0));
  final now = DateTime(2026, 9, 25, 7);

  test('ordina: disponibile, libero, della struttura, qualifica, carico', () {
    final ideal = buildOperator(id: 'ideal', lastName: 'Zeta');
    final busy = buildOperator(id: 'busy', lastName: 'Alfa');
    final otherFacility = buildOperator(
      id: 'other',
      lastName: 'Beta',
      primaryFacilityId: 'str-2',
    );
    final wrongQualification = buildOperator(
      id: 'wrong',
      lastName: 'Gamma',
      qualification: 'Educatore professionale',
    );
    final loaded = buildOperator(id: 'loaded', lastName: 'Delta');
    final suspended = buildOperator(
      id: 'suspended',
      status: OperatorStatus.sospeso,
    );
    final disabled = buildOperator(
      id: 'disabled',
      status: OperatorStatus.disabilitato,
    );

    final services = [
      buildService(id: 's1', operatorId: 'busy', start: atTime(day, 10, 30)),
      buildService(
        id: 's2',
        operatorId: 'loaded',
        start: atTime(day, 7, 0),
        duration: const Duration(hours: 2),
      ),
    ];

    final ranked = advisor.rank(
      operators: [
        busy,
        otherFacility,
        wrongQualification,
        loaded,
        ideal,
        suspended,
        disabled,
      ],
      services: services,
      slot: slot,
      facilityId: 'str-1',
      requiredQualifications: const ['OSS', 'ASA'],
      now: now,
    );

    expect(ranked.map((c) => c.operator.id), [
      'ideal',
      'loaded',
      'wrong',
      'other',
      'busy',
    ]);
    expect(ranked.first.isIdeal, isTrue);
    expect(
      ranked.firstWhere((c) => c.operator.id == 'loaded').servicesThatDay,
      1,
    );
    expect(ranked.last.overlapping.single.id, 's1');
  });

  test(
    'gli operatori sospesi compaiono solo se richiesto, i disabilitati mai',
    () {
      final ranked = advisor.rank(
        operators: [
          buildOperator(id: 'a'),
          buildOperator(id: 's', status: OperatorStatus.sospeso),
          buildOperator(id: 'd', status: OperatorStatus.disabilitato),
        ],
        services: const [],
        slot: slot,
        facilityId: 'str-1',
        now: now,
        includeNotAssignable: true,
      );
      expect(ranked.map((c) => c.operator.id), ['a', 's']);
      expect(ranked.last.isAssignable, isFalse);
    },
  );

  test('la struttura secondaria conta come appartenenza', () {
    final ranked = advisor.rank(
      operators: [
        buildOperator(
          id: 'multi',
          primaryFacilityId: 'str-2',
          secondaryFacilityIds: const ['str-1'],
        ),
      ],
      services: const [],
      slot: slot,
      facilityId: 'str-1',
      now: now,
    );
    expect(ranked.single.belongsToFacility, isTrue);
  });
}
