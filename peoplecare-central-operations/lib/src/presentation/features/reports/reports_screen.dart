import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/clock.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/screen_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/csv.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/charts.dart';
import '../../shared/widgets/data_table.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/kpi.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';

/// Periodi proposti per il report.
enum ReportPeriod {
  settimana('Questa settimana'),
  settimanaScorsa('Settimana scorsa'),
  ultimi30('Ultimi 30 giorni'),
  mese('Questo mese'),
  meseScorso('Mese scorso');

  const ReportPeriod(this.label);

  final String label;

  DateRange range(DateTime now) {
    final today = startOfDay(now);
    return switch (this) {
      settimana => DateRange.week(today),
      settimanaScorsa => DateRange.week(addDays(today, -7)),
      ultimi30 => DateRange(addDays(today, -29), addDays(today, 1)),
      mese => DateRange.month(today),
      meseScorso => DateRange.month(DateTime(today.year, today.month - 1)),
    };
  }
}

class ReportsController extends ScreenController {
  ReportsController({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {OperationalEventTopic.servizi},
         refreshDebounce: const Duration(seconds: 2),
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;

  ReportPeriod period = ReportPeriod.settimana;
  String? facilityId;
  OperationalReport? report;

  @override
  Future<void> fetch() async {
    report = await _repositories.reports.getOperationalReport(
      ReportQuery(period: period.range(clock.now()), facilityId: facilityId),
    );
  }

  void setPeriod(ReportPeriod value) {
    period = value;
    unawaited(load());
  }

  void setFacility(String? value) {
    facilityId = value;
    unawaited(load());
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = ReportsController(
      repositories: deps.repositories,
      clock: deps.clock,
    );
    unawaited(_controller.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setActive(SectionActivity.of(context));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export(OperationalReport report) async {
    final deps = context.deps;
    final rows = <List<Object?>>[
      [
        'Periodo',
        '${Fmt.date(report.period.start)} - ${Fmt.date(addDays(report.period.end, -1))}',
      ],
      [
        'Struttura',
        report.facilityId == null
            ? 'Tutte'
            : deps.reference.facilityName(report.facilityId),
      ],
      ['Servizi', report.totalServices],
      for (final status in ServiceStatus.values)
        [status.label, report.count(status)],
      [
        'Puntualità (entro ${report.onTimeToleranceMinutes} min)',
        Fmt.percent(report.punctualityRate),
      ],
      ['Ore programmate', Fmt.decimal(report.scheduledMinutes / 60)],
      ['Ore erogate', Fmt.decimal(report.deliveredMinutes / 60)],
      ['Richieste di modifica', report.changeRequestCount],
      [],
      [
        'Operatore',
        'Codice',
        'Servizi',
        'Completati',
        'Non eseguiti',
        'Annullati',
        'Ore programmate',
        'Ore erogate',
        'Ritardo medio (min)',
      ],
      for (final row in report.operators)
        [
          row.operatorName,
          row.operatorCode,
          row.totalServices,
          row.completed,
          row.notExecuted,
          row.cancelled,
          Fmt.decimal(row.scheduledMinutes / 60),
          Fmt.decimal(row.deliveredMinutes / 60),
          row.averageStartDelayMinutes == null
              ? ''
              : Fmt.decimal(row.averageStartDelayMinutes!),
        ],
    ];
    await saveCsv(
      context,
      fileName: timestampedFileName('report_operativo', deps.clock.now()),
      bytes: buildCsv(['Voce', 'Valore'], rows),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.reference]),
      builder: (context, _) {
        final report = _controller.report;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Report operativo',
              subtitle: report == null
                  ? null
                  : 'Periodo ${Fmt.date(report.period.start)} – '
                        '${Fmt.date(addDays(report.period.end, -1))} · calcolato su orari '
                        'programmati ed effettivi (app mobile)',
              actions: [
                FilterMenu<ReportPeriod>(
                  label: 'Periodo',
                  icon: Icons.date_range_outlined,
                  allowAll: false,
                  value: _controller.period,
                  options: [
                    for (final p in ReportPeriod.values)
                      FilterOption(p, p.label),
                  ],
                  onChanged: (value) {
                    if (value != null) _controller.setPeriod(value);
                  },
                ),
                FilterMenu<String>(
                  label: 'Struttura',
                  icon: Icons.apartment_outlined,
                  allLabel: 'Tutte',
                  value: _controller.facilityId,
                  options: [
                    for (final f in deps.reference.facilities)
                      FilterOption(f.id, f.name),
                  ],
                  onChanged: _controller.setFacility,
                ),
                OutlinedButton.icon(
                  onPressed: report == null
                      ? null
                      : () => unawaited(_export(report)),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Esporta CSV'),
                ),
              ],
            ),
            RefreshingBar(
              visible: _controller.isLoading && _controller.hasLoaded,
            ),
            Expanded(
              child: report == null
                  ? (_controller.error != null
                        ? ErrorView(
                            error: _controller.error!,
                            onRetry: _controller.load,
                          )
                        : const LoadingView(message: 'Calcolo del report…'))
                  : Opacity(
                      opacity: _controller.isLoading ? 0.6 : 1,
                      child: _ReportBody(report: report),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final OperationalReport report;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final now = deps.clock.now();
    final concluded =
        report.count(ServiceStatus.completato) +
        report.count(ServiceStatus.nonEseguito);
    final cancelled = report.count(ServiceStatus.annullato);
    final planned = report.totalServices - cancelled;
    final todayIndex = report.daily.indexWhere((d) => isSameDay(d.day, now));
    const stackSeries = [
      ChartColors.completed,
      ChartColors.notExecuted,
      ChartColors.planned,
      ChartColors.toPlan,
    ];
    List<num> stack(DailyServiceStat d) => [
      d.count(ServiceStatus.completato),
      d.count(ServiceStatus.nonEseguito),
      d.count(ServiceStatus.assegnato) + d.count(ServiceStatus.inCorso),
      d.count(ServiceStatus.daAssegnare) +
          d.count(ServiceStatus.daRiprogrammare),
    ];
    final dayLabel = report.daily.length <= 7
        ? (DateTime d) => Fmt.capitalize(Fmt.dayHeader(d))
        : (DateTime d) => Fmt.dateShort(d);

    final kpis = [
      KpiTile(
        icon: Icons.assignment_outlined,
        label: 'Servizi programmati',
        value: Fmt.integer(planned),
        caption: Fmt.count(cancelled, 'annullato escluso', 'annullati esclusi'),
      ),
      KpiTile(
        icon: Icons.check_circle_outline,
        label: 'Completati',
        value: Fmt.integer(report.count(ServiceStatus.completato)),
        caption: concluded == 0
            ? 'Nessun servizio concluso'
            : '${Fmt.percent(report.completionRate)} dei conclusi',
        color: ChartColors.completed.of(context),
      ),
      KpiTile(
        icon: Icons.report_gmailerrorred_outlined,
        label: 'Non eseguiti',
        value: Fmt.integer(report.count(ServiceStatus.nonEseguito)),
        caption: 'Segnalati dagli operatori',
        color: palette.danger,
      ),
      KpiTile(
        icon: Icons.timer_outlined,
        label: 'Puntualità avvio',
        value: Fmt.percent(report.punctualityRate),
        caption: report.averageStartDelayMinutes == null
            ? 'Nessun avvio registrato'
            : 'Entro ${report.onTimeToleranceMinutes} min · medio '
                  '${report.averageStartDelayMinutes!.round()} min',
      ),
      KpiTile(
        icon: Icons.schedule,
        label: 'Ore erogate',
        value: Fmt.hoursFromMinutes(report.deliveredMinutes),
        caption:
            'su ${Fmt.hoursFromMinutes(report.scheduledMinutes)} programmate',
        color: palette.accent,
      ),
      KpiTile(
        icon: Icons.edit_calendar_outlined,
        label: 'Richieste di modifica',
        value: Fmt.integer(report.changeRequestCount),
        caption: planned == 0
            ? '—'
            : '${Fmt.decimal(report.changeRequestCount / planned * 100)} ogni 100 servizi',
        color: palette.accent,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1200;
        final kpiColumns = constraints.maxWidth >= 1400 ? 6 : 3;
        final kpiWidth =
            (constraints.maxWidth - 48 - 12 * (kpiColumns - 1)) / kpiColumns;
        Widget pair(Widget a, Widget b) => wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 16),
                  Expanded(child: b),
                ],
              )
            : Column(children: [a, const SizedBox(height: 16), b]);

        final topOperators = report.operators.take(12).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final kpi in kpis) SizedBox(width: kpiWidth, child: kpi),
              ],
            ),
            const SizedBox(height: 16),
            ChartCard(
              title: 'Servizi per giorno',
              subtitle: 'Esiti dei servizi programmati (annullati esclusi)',
              legend: const ChartLegend(series: stackSeries),
              chart: StackedColumnChart(
                labels: [for (final d in report.daily) dayLabel(d.day)],
                values: [for (final d in report.daily) stack(d)],
                series: stackSeries,
                highlight: todayIndex < 0 ? null : todayIndex,
              ),
              tableHeader: [
                'Giorno',
                for (final s in stackSeries) s.label,
                'Annullati',
              ],
              tableRows: [
                for (final d in report.daily)
                  [
                    Fmt.capitalize(Fmt.dayMedium(d.day)),
                    for (final v in stack(d)) Fmt.integer(v.toInt()),
                    Fmt.integer(d.count(ServiceStatus.annullato)),
                  ],
              ],
            ),
            const SizedBox(height: 16),
            pair(
              ChartCard(
                title: 'Ore erogate per operatore',
                subtitle: topOperators.length < report.operators.length
                    ? 'Primi ${topOperators.length} operatori; elenco completo nella tabella sotto'
                    : 'Da orari effettivi di inizio e fine',
                chart: topOperators.isEmpty
                    ? const EmptyView(title: 'Nessun dato', compact: true)
                    : HorizontalBarChart(
                        items: [
                          for (final row in topOperators)
                            BarItem(
                              label: row.operatorName,
                              value: row.deliveredMinutes,
                              valueLabel: Fmt.hoursFromMinutes(
                                row.deliveredMinutes,
                              ),
                              tooltip:
                                  '${row.operatorName}: ${Fmt.hoursFromMinutes(row.deliveredMinutes)} erogate '
                                  'su ${Fmt.hoursFromMinutes(row.scheduledMinutes)} programmate',
                            ),
                        ],
                      ),
                tableHeader: const [
                  'Operatore',
                  'Ore erogate',
                  'Ore programmate',
                ],
                tableRows: [
                  for (final row in report.operators)
                    [
                      row.operatorName,
                      Fmt.hoursFromMinutes(row.deliveredMinutes),
                      Fmt.hoursFromMinutes(row.scheduledMinutes),
                    ],
                ],
              ),
              ChartCard(
                title: 'Servizi per tipologia',
                subtitle: 'Numero di servizi nel periodo',
                chart: HorizontalBarChart(
                  items: [
                    for (final row in report.serviceTypes.take(12))
                      BarItem(
                        label: row.label,
                        value: row.totalServices,
                        valueLabel: Fmt.integer(row.totalServices),
                        tooltip:
                            '${row.label}: ${Fmt.count(row.totalServices, 'servizio', 'servizi')}, '
                            '${Fmt.count(row.completed, 'completato', 'completati')}',
                      ),
                  ],
                ),
                tableHeader: const [
                  'Tipologia',
                  'Servizi',
                  'Completati',
                  'Ore erogate',
                ],
                tableRows: [
                  for (final row in report.serviceTypes)
                    [
                      row.label,
                      Fmt.integer(row.totalServices),
                      Fmt.integer(row.completed),
                      Fmt.hoursFromMinutes(row.deliveredMinutes),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            pair(
              ChartCard(
                title: 'Richieste di modifica per motivo',
                subtitle: 'Inviate dagli operatori sui servizi del periodo',
                chart: HorizontalBarChart(
                  items: [
                    for (final reason in ChangeRequestReason.values)
                      BarItem(
                        label: reason.label,
                        value: report.changeRequestsByReason[reason] ?? 0,
                        valueLabel: Fmt.integer(
                          report.changeRequestsByReason[reason] ?? 0,
                        ),
                      ),
                  ],
                ),
                tableHeader: const ['Motivo', 'Richieste'],
                tableRows: [
                  for (final reason in ChangeRequestReason.values)
                    [
                      reason.label,
                      Fmt.integer(report.changeRequestsByReason[reason] ?? 0),
                    ],
                ],
              ),
              ChartCard(
                title: 'Servizi per struttura',
                subtitle: 'Numero di servizi nel periodo',
                chart: HorizontalBarChart(
                  labelWidth: 220,
                  items: [
                    for (final row in report.facilities)
                      BarItem(
                        label: row.facilityName,
                        value: row.totalServices,
                        valueLabel: Fmt.integer(row.totalServices),
                        tooltip:
                            '${row.facilityName}: ${Fmt.count(row.totalServices, 'servizio', 'servizi')}, '
                            '${Fmt.hoursFromMinutes(row.deliveredMinutes)} erogate',
                      ),
                  ],
                ),
                tableHeader: const [
                  'Struttura',
                  'Servizi',
                  'Completati',
                  'Ore erogate',
                ],
                tableRows: [
                  for (final row in report.facilities)
                    [
                      row.facilityName,
                      Fmt.integer(row.totalServices),
                      Fmt.integer(row.completed),
                      Fmt.hoursFromMinutes(row.deliveredMinutes),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              title: 'Dettaglio per operatore',
              subtitle:
                  'Ore e puntualità calcolate da actual_start / actual_end',
              icon: Icons.table_chart_outlined,
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 44.0 + 52 * report.operators.length.clamp(1, 14),
                child: AppDataTable<OperatorReportRow>(
                  items: report.operators,
                  idOf: (row) => row.operatorId,
                  rowHeight: 48,
                  columns: [
                    TableColumnDef(
                      label: 'Operatore',
                      flex: 3,
                      minWidth: 200,
                      cell: (context, row) => CellText(
                        row.operatorName,
                        secondary: row.operatorCode,
                        bold: true,
                      ),
                    ),
                    for (final (label, value) in [
                      (
                        'Servizi',
                        (OperatorReportRow r) => '${r.totalServices}',
                      ),
                      ('Completati', (OperatorReportRow r) => '${r.completed}'),
                      (
                        'Non eseguiti',
                        (OperatorReportRow r) => '${r.notExecuted}',
                      ),
                      ('Annullati', (OperatorReportRow r) => '${r.cancelled}'),
                      (
                        'Ore programmate',
                        (OperatorReportRow r) =>
                            Fmt.hoursFromMinutes(r.scheduledMinutes),
                      ),
                      (
                        'Ore erogate',
                        (OperatorReportRow r) =>
                            Fmt.hoursFromMinutes(r.deliveredMinutes),
                      ),
                      (
                        'Ritardo medio',
                        (OperatorReportRow r) =>
                            r.averageStartDelayMinutes == null
                            ? '—'
                            : '${r.averageStartDelayMinutes!.round()} min',
                      ),
                    ])
                      TableColumnDef<OperatorReportRow>(
                        label: label,
                        width: 130,
                        alignEnd: true,
                        cell: (context, row) => Text(
                          value(row),
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
