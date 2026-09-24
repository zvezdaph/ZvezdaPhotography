import 'package:flutter/material.dart';

import '../../../core/paging.dart';
import '../../theme/app_palette.dart';
import '../formatters.dart';
import 'states.dart';

/// Definizione di una colonna di [AppDataTable].
class TableColumnDef<T> {
  const TableColumnDef({
    required this.label,
    required this.cell,
    this.width,
    this.flex = 1,
    this.sortKey,
    this.alignEnd = false,
    this.minWidth = 80,
  });

  final String label;
  final Widget Function(BuildContext context, T item) cell;

  /// Larghezza fissa; se `null` la colonna si espande secondo [flex].
  final double? width;
  final int flex;

  /// Chiave di ordinamento; `null` = colonna non ordinabile.
  final Object? sortKey;
  final bool alignEnd;

  /// Larghezza minima usata per calcolare lo scorrimento orizzontale.
  final double minWidth;
}

/// Tabella desktop: intestazione fissa, righe con hover e selezione,
/// ordinamento per colonna, righe espandibili e scorrimento orizzontale
/// quando lo spazio non basta.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.items,
    required this.idOf,
    this.onRowTap,
    this.onRowDoubleTap,
    this.selectedId,
    this.sortKey,
    this.sortDescending = false,
    this.onSort,
    this.rowHeight = 52,
    this.isLoading = false,
    this.emptyTitle = 'Nessun risultato',
    this.emptyMessage,
    this.emptyIcon = Icons.search_off,
    this.rowAccent,
    this.expandedIds = const {},
    this.expandedBuilder,
    this.controller,
  });

  final List<TableColumnDef<T>> columns;
  final List<T> items;
  final String Function(T item) idOf;
  final ValueChanged<T>? onRowTap;
  final ValueChanged<T>? onRowDoubleTap;
  final String? selectedId;
  final Object? sortKey;
  final bool sortDescending;
  final ValueChanged<Object>? onSort;
  final double rowHeight;
  final bool isLoading;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;

  /// Colore della barra laterale della riga (es. priorità urgente).
  final Color? Function(T item)? rowAccent;
  final Set<String> expandedIds;
  final Widget Function(BuildContext context, T item)? expandedBuilder;
  final ScrollController? controller;

  static const _horizontalPadding = 12.0;

  double get _minWidth =>
      columns.fold<double>(
        0,
        (sum, column) => sum + (column.width ?? column.minWidth),
      ) +
      _horizontalPadding * 2 +
      4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < _minWidth
            ? _minWidth
            : constraints.maxWidth;
        final table = SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Column(
            children: [
              _Header<T>(table: this),
              Divider(height: 1, color: context.palette.border),
              Expanded(child: _body(context)),
            ],
          ),
        );
        if (width == constraints.maxWidth) return table;
        return Scrollbar(
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    if (items.isEmpty) {
      if (isLoading) return const LoadingView();
      return EmptyView(
        title: emptyTitle,
        message: emptyMessage,
        icon: emptyIcon,
      );
    }
    return Stack(
      children: [
        Scrollbar(
          controller: controller,
          child: ListView.builder(
            controller: controller,
            itemCount: items.length,
            itemBuilder: (context, index) => _row(context, items[index], index),
          ),
        ),
        if (isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, T item, int index) {
    final palette = context.palette;
    final id = idOf(item);
    final selected = id == selectedId;
    final expanded = expandedIds.contains(id) && expandedBuilder != null;
    final accent = rowAccent?.call(item);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          child: InkWell(
            onTap: onRowTap == null ? null : () => onRowTap!(item),
            onDoubleTap: onRowDoubleTap == null
                ? null
                : () => onRowDoubleTap!(item),
            hoverColor: palette.hover,
            child: Container(
              constraints: BoxConstraints(minHeight: rowHeight),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color:
                        accent ??
                        (selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent),
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: _horizontalPadding - 3,
              ),
              child: Row(
                children: [
                  for (final column in columns)
                    _cellBox(
                      column,
                      Align(
                        alignment: column.alignEnd
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: column.cell(context, item),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (expanded) expandedBuilder!(context, item),
        Divider(height: 1, color: palette.border),
      ],
    );
  }

  Widget _cellBox(TableColumnDef<T> column, Widget child) {
    if (column.width != null) {
      return SizedBox(width: column.width, child: child);
    }
    return Expanded(flex: column.flex, child: child);
  }
}

class _Header<T> extends StatelessWidget {
  const _Header({required this.table});

  final AppDataTable<T> table;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 42,
      color: palette.surfaceMuted,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDataTable._horizontalPadding,
      ),
      child: Row(
        children: [
          for (final column in table.columns)
            table._cellBox(column, _headerCell(context, column)),
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, TableColumnDef<T> column) {
    final palette = context.palette;
    final sortable = column.sortKey != null && table.onSort != null;
    final active = sortable && column.sortKey == table.sortKey;
    final text = Text(
      column.label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: active ? palette.textPrimary : palette.textMuted,
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: column.alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(child: text),
        if (sortable)
          Icon(
            active
                ? (table.sortDescending
                      ? Icons.arrow_downward
                      : Icons.arrow_upward)
                : Icons.unfold_more,
            size: 14,
            color: active ? palette.textPrimary : palette.textMuted,
          ),
      ],
    );
    return Align(
      alignment: column.alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: sortable
            ? InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => table.onSort!(column.sortKey!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: content,
                ),
              )
            : content,
      ),
    );
  }
}

/// Piè di pagina con conteggio e navigazione tra pagine.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.result,
    required this.onPage,
    this.itemLabel = 'risultati',
  });

  final PagedResult<Object?> result;
  final ValueChanged<int> onPage;
  final String itemLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Text(
            result.total == 0
                ? 'Nessun elemento'
                : '${Fmt.integer(result.firstIndex)}–${Fmt.integer(result.lastIndex)} '
                      'di ${Fmt.integer(result.total)} $itemLabel',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          const Spacer(),
          Text(
            'Pagina ${result.page} di ${result.pageCount}',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Prima pagina',
            onPressed: result.hasPrevious ? () => onPage(1) : null,
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: 'Pagina precedente',
            onPressed: result.hasPrevious
                ? () => onPage(result.page - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Pagina successiva',
            onPressed: result.hasNext ? () => onPage(result.page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Ultima pagina',
            onPressed: result.hasNext ? () => onPage(result.pageCount) : null,
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
    );
  }
}

/// Testo principale + secondario in una cella.
class CellText extends StatelessWidget {
  const CellText(this.primary, {super.key, this.secondary, this.bold = false});

  final String primary;
  final String? secondary;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            color: palette.textPrimary,
          ),
        ),
        if (secondary != null && secondary!.isNotEmpty)
          Text(
            secondary!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
          ),
      ],
    );
  }
}
