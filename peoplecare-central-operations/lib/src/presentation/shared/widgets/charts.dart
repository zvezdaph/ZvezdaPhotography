import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../formatters.dart';

/// Serie di un grafico con i colori validati per tema chiaro e scuro
/// (controllo daltonismo/contrasto eseguito con lo strumento di validazione
/// della palette; vedi README).
class ChartSeries {
  const ChartSeries(this.label, {required this.light, required this.dark});

  final String label;
  final Color light;
  final Color dark;

  Color of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Colori dei grafici.
abstract final class ChartColors {
  /// Serie singola (slot 1).
  static const single = ChartSeries(
    'Valore',
    light: Color(0xFF2A78D6),
    dark: Color(0xFF3987E5),
  );

  // Esiti dei servizi, nell'ordine di impilamento validato.
  static const completed = ChartSeries(
    'Completati',
    light: Color(0xFF1E8A4C),
    dark: Color(0xFF2F9E5F),
  );
  static const notExecuted = ChartSeries(
    'Non eseguiti',
    light: Color(0xFFE34948),
    dark: Color(0xFFE66767),
  );
  static const planned = ChartSeries(
    'Da svolgere',
    light: Color(0xFF2A78D6),
    dark: Color(0xFF3987E5),
  );
  static const toPlan = ChartSeries(
    'Da pianificare',
    light: Color(0xFFEDA100),
    dark: Color(0xFFC98500),
  );
}

/// Legenda (sempre presente con due o più serie).
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.series});

  final List<ChartSeries> series;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final s in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: s.of(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                s.label,
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Valore "pulito" per la scala dell'asse (1, 2, 5 × 10^n).
double niceCeiling(double value) {
  if (value <= 0) return 1;
  final exponent = pow(10, (log(value) / ln10).floor()).toDouble();
  final fraction = value / exponent;
  final nice = fraction <= 1
      ? 1
      : fraction <= 2
      ? 2
      : fraction <= 5
      ? 5
      : 10;
  return nice * exponent;
}

/// Istogramma a colonne impilate con griglia sottile, separatori da 2 px,
/// estremità arrotondate e tooltip per colonna.
class StackedColumnChart extends StatelessWidget {
  const StackedColumnChart({
    super.key,
    required this.labels,
    required this.values,
    required this.series,
    this.height = 240,
    this.highlight,
  });

  /// Etichette dell'asse X.
  final List<String> labels;

  /// Per ogni colonna, i valori delle serie (dal basso verso l'alto).
  final List<List<num>> values;
  final List<ChartSeries> series;
  final double height;

  /// Indice della colonna da evidenziare (es. oggi).
  final int? highlight;

  static const _axisWidth = 36.0;
  static const _labelBand = 22.0;
  static const _maxBar = 24.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final totals = [for (final v in values) v.fold<num>(0, (a, b) => a + b)];
    final maxTotal = totals.isEmpty ? 0 : totals.reduce(max);
    final top = niceCeiling(maxTotal.toDouble());
    const ticks = 4;
    const topPadding = 10.0;
    final plotHeight = height - _labelBand - topPadding;
    final labelEvery = max(1, (labels.length / 16).ceil());
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _axisWidth,
            child: Stack(
              children: [
                for (var i = 0; i <= ticks; i++)
                  Positioned(
                    right: 6,
                    top: topPadding + plotHeight - plotHeight * i / ticks - 7,
                    child: Text(
                      Fmt.integer((top * i / ticks).round()),
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: topPadding),
                SizedBox(
                  height: plotHeight,
                  child: CustomPaint(
                    painter: _GridPainter(
                      ticks: ticks,
                      color: palette.gridLine,
                      baseline: palette.borderStrong,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < values.length; i++)
                          Expanded(
                            child: _Column(
                              values: values[i],
                              series: series,
                              top: top,
                              height: plotHeight,
                              maxBar: _maxBar,
                              label: labels[i],
                              highlighted: highlight == i,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: _labelBand,
                  child: Row(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: Text(
                            i % labelEvery == 0 ? labels[i] : '',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 11,
                              color: highlight == i
                                  ? palette.textPrimary
                                  : palette.textMuted,
                              fontWeight: highlight == i
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.values,
    required this.series,
    required this.top,
    required this.height,
    required this.maxBar,
    required this.label,
    required this.highlighted,
  });

  final List<num> values;
  final List<ChartSeries> series;
  final double top;
  final double height;
  final double maxBar;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = values.fold<num>(0, (a, b) => a + b);
    final tooltip = [
      '$label · totale ${Fmt.integer(total.toInt())}',
      for (var i = 0; i < series.length; i++)
        '${series[i].label}: ${Fmt.integer(values[i].toInt())}',
    ].join('\n');
    final segments = <Widget>[];
    // Spazio riservato ai separatori tra i segmenti.
    final usable = height - 2.0 * series.length;
    // Dall'alto verso il basso: l'ultima serie sta in cima.
    var first = true;
    for (var i = series.length - 1; i >= 0; i--) {
      final value = values[i];
      if (value <= 0) continue;
      final segmentHeight = max(1.0, value / top * usable);
      segments.add(
        Container(
          height: segmentHeight,
          margin: EdgeInsets.only(top: first ? 0 : 2),
          decoration: BoxDecoration(
            color: series[i].of(context),
            borderRadius: first
                ? const BorderRadius.vertical(top: Radius.circular(4))
                : null,
          ),
        ),
      );
      first = false;
    }
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 150),
      child: Container(
        color: highlighted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        alignment: Alignment.bottomCenter,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = min(maxBar, constraints.maxWidth * 0.62);
            return SizedBox(
              width: width,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: segments.isEmpty
                    ? [Container(height: 1, color: palette.border)]
                    : segments,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.ticks,
    required this.color,
    required this.baseline,
  });

  final int ticks;
  final Color color;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 1; i <= ticks; i++) {
      final y = size.height - size.height * i / ticks;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.ticks != ticks;
}

/// Voce di un grafico a barre orizzontali.
class BarItem {
  const BarItem({
    required this.label,
    required this.value,
    required this.valueLabel,
    this.tooltip,
  });

  final String label;
  final num value;
  final String valueLabel;
  final String? tooltip;
}

/// Barre orizzontali a serie singola, valore in punta alla barra.
class HorizontalBarChart extends StatelessWidget {
  const HorizontalBarChart({
    super.key,
    required this.items,
    this.labelWidth = 170,
    this.series = ChartColors.single,
  });

  final List<BarItem> items;
  final double labelWidth;
  final ChartSeries series;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final maxValue = items.isEmpty
        ? 1
        : items.map((i) => i.value).reduce(max).clamp(1, double.infinity);
    final valueStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: palette.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Spazio per il valore in punta: misurato sull'etichetta più larga, così
    // la barra più lunga non spinge il testo fuori dalla scheda.
    final baseStyle = DefaultTextStyle.of(context).style.merge(valueStyle);
    final textScaler = MediaQuery.textScalerOf(context);
    var widestValue = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.valueLabel, style: baseStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      widestValue = max(widestValue, painter.width);
      painter.dispose();
    }
    return Column(
      children: [
        for (final item in items)
          Tooltip(
            message: item.tooltip ?? '${item.label}: ${item.valueLabel}',
            waitDuration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final valueSpace = min(
                          widestValue + 12,
                          constraints.maxWidth / 2,
                        );
                        final available = max(
                          0.0,
                          constraints.maxWidth - valueSpace,
                        );
                        final width = item.value <= 0
                            ? 0.0
                            : max(2.0, available * item.value / maxValue);
                        return Row(
                          children: [
                            Container(
                              width: width,
                              height: 14,
                              decoration: BoxDecoration(
                                color: series.of(context),
                                borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item.valueLabel,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: valueStyle,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Scheda che alterna grafico e tabella equivalente (accessibilità).
class ChartCard extends StatefulWidget {
  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.chart,
    required this.tableHeader,
    required this.tableRows,
    this.legend,
  });

  final String title;
  final String? subtitle;
  final Widget chart;
  final Widget? legend;
  final List<String> tableHeader;
  final List<List<String>> tableRows;

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _table ? 'Mostra grafico' : 'Mostra tabella',
                onPressed: () => setState(() => _table = !_table),
                icon: Icon(
                  _table ? Icons.bar_chart_outlined : Icons.table_rows_outlined,
                ),
              ),
            ],
          ),
          if (widget.legend != null && !_table) ...[
            const SizedBox(height: 8),
            widget.legend!,
          ],
          const SizedBox(height: 12),
          if (_table)
            _SimpleTable(header: widget.tableHeader, rows: widget.tableRows)
          else
            widget.chart,
        ],
      ),
    );
  }
}

class _SimpleTable extends StatelessWidget {
  const _SimpleTable({required this.header, required this.rows});

  final List<String> header;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    TextStyle cell(bool head) => TextStyle(
      fontSize: 12.5,
      fontWeight: head ? FontWeight.w700 : FontWeight.w400,
      color: head ? palette.textSecondary : palette.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Table(
          columnWidths: const {0: FlexColumnWidth(2)},
          border: TableBorder(
            horizontalInside: BorderSide(color: palette.border),
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(color: palette.surfaceMuted),
              children: [
                for (var i = 0; i < header.length; i++)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      header[i],
                      textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                      style: cell(true),
                    ),
                  ),
              ],
            ),
            for (final row in rows)
              TableRow(
                children: [
                  for (var i = 0; i < row.length; i++)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        row[i],
                        textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                        style: cell(false),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
