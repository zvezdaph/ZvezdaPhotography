import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../domain/domain.dart';
import '../app_scope.dart';
import '../app_state/navigation_controller.dart';
import '../features/operators/operator_detail_panel.dart';
import '../features/service_detail/service_detail_panel.dart';
import '../shared/formatters.dart';
import '../shared/widgets/badges.dart';
import '../shared/widgets/layout.dart';
import '../theme/app_palette.dart';

/// Ricerca rapida (Ctrl+K) su servizi, operatori e pazienti.
Future<void> showQuickSearch(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.3),
  builder: (_) => const _QuickSearchDialog(),
);

sealed class _Result {
  const _Result();
}

final class _ServiceResult extends _Result {
  const _ServiceResult(this.service);
  final Service service;
}

final class _OperatorResult extends _Result {
  const _OperatorResult(this.operator);
  final Operator operator;
}

final class _PatientResult extends _Result {
  const _PatientResult(this.patient);
  final Patient patient;
}

class _QuickSearchDialog extends StatefulWidget {
  const _QuickSearchDialog();

  @override
  State<_QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends State<_QuickSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Service> _upcoming = const [];
  List<Service> _recent = const [];
  List<Operator> _operators = const [];
  List<Patient> _patients = const [];
  bool _searching = false;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(text));
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    final generation = ++_generation;
    if (query.length < 2) {
      setState(() {
        _upcoming = const [];
        _recent = const [];
        _operators = const [];
        _patients = const [];
      });
      return;
    }
    final deps = context.deps;
    setState(() => _searching = true);
    final today = startOfDay(deps.clock.now());
    try {
      // Prima i servizi di oggi e dei prossimi giorni (in ordine di orario),
      // poi quelli recenti dal più vicino al più lontano.
      final results = await Future.wait<Object>([
        deps.repositories.services.searchServices(
          ServiceQuery(
            search: query,
            range: DateRange(today, addDays(today, 31)),
          ),
          page: const PageRequest(pageSize: 6),
        ),
        deps.repositories.services.searchServices(
          ServiceQuery(
            search: query,
            range: DateRange(addDays(today, -14), today),
            descending: true,
          ),
          page: const PageRequest(pageSize: 4),
        ),
        deps.repositories.patients.searchPatients(query, limit: 6),
      ]);
      if (!mounted || generation != _generation) return;
      final upcoming = (results[0] as PagedResult<Service>).items;
      final upcomingIds = {for (final s in upcoming) s.id};
      setState(() {
        _upcoming = upcoming;
        _recent = (results[1] as PagedResult<Service>).items
            .where((s) => !upcomingIds.contains(s.id))
            .toList();
        _patients = results[2] as List<Patient>;
        _operators = deps.reference.operators
            .where(
              (o) => matchesSearch(query, [
                o.firstName,
                o.lastName,
                o.code,
                o.qualification,
              ]),
            )
            .take(6)
            .toList();
      });
    } on RepositoryException {
      // La ricerca rapida ignora gli errori: l'utente può riprovare.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  List<_Result> get _results => [
    for (final s in _upcoming) _ServiceResult(s),
    for (final s in _recent) _ServiceResult(s),
    for (final o in _operators) _OperatorResult(o),
    for (final p in _patients) _PatientResult(p),
  ];

  void _open(_Result result) {
    final navigator = Navigator.of(context);
    final deps = context.deps;
    final rootContext = navigator.context;
    navigator.pop();
    switch (result) {
      case _ServiceResult(:final service):
        unawaited(showServiceDetail(rootContext, service.id));
      case _OperatorResult(:final operator):
        unawaited(showOperatorDetail(rootContext, operator.id));
      case _PatientResult(:final patient):
        deps.navigation.go(
          AppSection.services,
          intent: ServicesFilterIntent(patientId: patient.id),
        );
    }
  }

  Widget _serviceTile(Service s) => _ResultTile(
    icon: Icons.assignment_outlined,
    title: '${s.code} · ${s.patient.fullName}',
    subtitle:
        '${s.kind.label} · ${Fmt.slot(s.scheduledStart, s.scheduledEnd)} · '
        '${context.deps.reference.operatorName(s.operatorId)}',
    trailing: ServiceStatusBadge(s.status, dense: true),
    onTap: () => _open(_ServiceResult(s)),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final results = _results;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Material(
        color: palette.surface,
        elevation: 16,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 680,
          height: 520,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _onChanged,
                  onSubmitted: (_) {
                    if (results.isNotEmpty) _open(results.first);
                  },
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText:
                        'Codice servizio, paziente, operatore, indirizzo…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              Divider(height: 1, color: palette.border),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          _controller.text.trim().length < 2
                              ? 'Digita almeno 2 caratteri. Invio apre il primo risultato.'
                              : (_searching ? 'Ricerca…' : 'Nessun risultato'),
                          style: TextStyle(color: palette.textMuted),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        children: [
                          if (_upcoming.isNotEmpty) ...[
                            const _GroupHeader('Servizi · oggi e prossimi'),
                            for (final s in _upcoming) _serviceTile(s),
                          ],
                          if (_recent.isNotEmpty) ...[
                            const _GroupHeader('Servizi · ultimi 14 giorni'),
                            for (final s in _recent) _serviceTile(s),
                          ],
                          if (_operators.isNotEmpty) ...[
                            const _GroupHeader('Operatori'),
                            for (final o in _operators)
                              _ResultTile(
                                leading: InitialsAvatar(
                                  initials: o.initials,
                                  colorKey: o.id,
                                  size: 30,
                                ),
                                title: '${o.fullName} · ${o.code}',
                                subtitle:
                                    '${o.qualification} · ${context.deps.reference.facilityName(o.primaryFacilityId)}',
                                trailing: OperatorStatusBadge(
                                  o.status,
                                  dense: true,
                                ),
                                onTap: () => _open(_OperatorResult(o)),
                              ),
                          ],
                          if (_patients.isNotEmpty) ...[
                            const _GroupHeader('Pazienti'),
                            for (final p in _patients)
                              _ResultTile(
                                icon: Icons.personal_injury_outlined,
                                title: '${p.fullName} · ${p.code}',
                                subtitle:
                                    '${p.fullAddress ?? ''} · mostra i servizi',
                                onTap: () => _open(_PatientResult(p)),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
    child: SectionLabel(text, padding: EdgeInsets.zero),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.leading,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      hoverColor: palette.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            leading ?? Icon(icon, size: 22, color: palette.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}
