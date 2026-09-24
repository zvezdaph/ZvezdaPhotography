import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/navigation_controller.dart';
import '../../app_state/screen_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/data_table.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../operators/operator_detail_panel.dart';
import '../service_detail/service_detail_panel.dart';
import 'attachments.dart';
import 'document_list.dart';

class DocumentsController extends ScreenController {
  DocumentsController({required PeopleCareRepositories repositories})
    : _repositories = repositories,
      super(
        events: repositories.events,
        topics: const {OperationalEventTopic.documenti},
      );

  final PeopleCareRepositories _repositories;

  static const pageSize = 50;

  DocumentOwnerType? ownerType;
  Set<DocumentCategory> categories = {};
  DocumentSource? source;
  bool pendingOnly = false;
  String search = '';
  int page = 1;

  PagedResult<DocumentInfo> result = const PagedResult(
    items: [],
    total: 0,
    page: 1,
    pageSize: pageSize,
  );

  @override
  Future<void> fetch() async {
    result = await _repositories.documents.searchDocuments(
      DocumentQuery(
        ownerType: ownerType,
        categories: categories,
        source: source,
        pendingReviewOnly: pendingOnly,
        search: search.isEmpty ? null : search,
      ),
      page: PageRequest(page: page, pageSize: pageSize),
    );
  }

  void _changed() {
    page = 1;
    unawaited(load());
  }

  void setOwnerType(DocumentOwnerType? value) {
    ownerType = value;
    _changed();
  }

  void setCategories(Set<DocumentCategory> value) {
    categories = value;
    _changed();
  }

  void setSource(DocumentSource? value) {
    source = value;
    _changed();
  }

  void setPendingOnly(bool value) {
    pendingOnly = value;
    _changed();
  }

  void setSearch(String value) {
    search = value;
    _changed();
  }

  void goToPage(int value) {
    page = value;
    unawaited(load());
  }
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late final DocumentsController _controller;
  late final NavigationController _navigation;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = DocumentsController(repositories: deps.repositories);
    _navigation = deps.navigation;
    _applyIntent();
    unawaited(_controller.load());
    _navigation.addListener(_onNavigation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setActive(SectionActivity.of(context));
  }

  @override
  void dispose() {
    _navigation.removeListener(_onNavigation);
    _controller.dispose();
    super.dispose();
  }

  bool _applyIntent() {
    final intent = _navigation.takeIntent(AppSection.documents);
    if (intent is! DocumentsIntent) return false;
    _controller.pendingOnly = intent.pendingReviewOnly;
    _controller.ownerType = intent.ownerType;
    _controller.page = 1;
    return true;
  }

  void _onNavigation() {
    if (_navigation.current != AppSection.documents) return;
    if (_applyIntent()) unawaited(_controller.load());
  }

  Future<void> _upload() async {
    final owner = await showDialog<DocumentOwner>(
      context: context,
      builder: (_) => const _OwnerPickerDialog(),
    );
    if (owner == null || !mounted) return;
    final uploaded = await showUploadDocumentsDialog(context, owner: owner);
    if (uploaded.isNotEmpty) await _controller.refresh();
  }

  void _openOwner(DocumentInfo document) {
    final id = document.owner.id;
    switch (document.owner.type) {
      case DocumentOwnerType.servizio:
        if (id != null) {
          unawaited(
            showServiceDetail(
              context,
              id,
              initialTab: ServiceDetailTab.documenti,
            ),
          );
        }
      case DocumentOwnerType.operatore:
        if (id != null) unawaited(showOperatorDetail(context, id));
      case DocumentOwnerType.paziente:
        if (id != null) {
          context.deps.navigation.go(
            AppSection.services,
            intent: ServicesFilterIntent(patientId: id),
          );
        }
      case DocumentOwnerType.centrale:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.counters]),
      builder: (context, _) {
        final c = _controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Documenti',
              subtitle:
                  'Archivio dei documenti di servizi, operatori, pazienti e '
                  'della Centrale.',
              actions: [
                FilledButton.icon(
                  onPressed: () => unawaited(_upload()),
                  icon: const Icon(Icons.upload_file_outlined, size: 19),
                  label: const Text('Carica documenti'),
                ),
              ],
            ),
            if (deps.counters.documentsToReview > 0 && !c.pendingOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: InlineBanner(
                  style: severityStyle(
                    context,
                    NotificationSeverity.attenzione,
                  ),
                  title:
                      '${Fmt.count(deps.counters.documentsToReview, 'documento ricevuto', 'documenti ricevuti')} '
                      'dal territorio da verificare',
                  message: 'Fogli firma, verbali e foto inviati dagli operatori con l\'app mobile.',
                  action: TextButton(
                    onPressed: () => c.setPendingOnly(true),
                    child: const Text('Mostra'),
                  ),
                ),
              ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<DocumentOwnerType?>(
                          showSelectedIcon: false,
                          segments: [
                            const ButtonSegment(
                              value: null,
                              label: Text('Tutti'),
                            ),
                            for (final type in DocumentOwnerType.values)
                              ButtonSegment(
                                value: type,
                                label: Text(type.pluralLabel),
                              ),
                          ],
                          selected: {c.ownerType},
                          onSelectionChanged: (value) =>
                              c.setOwnerType(value.first),
                        ),
                      ),
                    ),
                    FilterBar(
                      children: [
                        SearchField(
                          hint: 'Titolo, file, associato a…',
                          initialValue: c.search,
                          onChanged: c.setSearch,
                        ),
                        MultiFilterMenu<DocumentCategory>(
                          label: 'Categoria',
                          icon: Icons.label_outline,
                          values: c.categories,
                          allLabel: 'Tutte',
                          options: [
                            for (final category in DocumentCategory.values)
                              FilterOption(category, category.label),
                          ],
                          onChanged: c.setCategories,
                        ),
                        FilterMenu<DocumentSource>(
                          label: 'Origine',
                          icon: Icons.input,
                          allLabel: 'Tutte',
                          value: c.source,
                          options: [
                            for (final source in DocumentSource.values)
                              FilterOption(source, source.label),
                          ],
                          onChanged: c.setSource,
                        ),
                        FilterChip(
                          avatar: Icon(
                            Icons.fact_check_outlined,
                            size: 17,
                            color: palette.warning,
                          ),
                          label: const Text('Solo da verificare'),
                          selected: c.pendingOnly,
                          onSelected: c.setPendingOnly,
                        ),
                      ],
                    ),
                    Divider(height: 1, color: palette.border),
                    Expanded(
                      child: c.error != null && !c.hasLoaded
                          ? ErrorView(error: c.error!, onRetry: c.load)
                          : _table(context),
                    ),
                    PaginationBar(
                      result: c.result,
                      itemLabel: 'documenti',
                      onPage: c.goToPage,
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

  Widget _table(BuildContext context) {
    final palette = context.palette;
    final now = context.deps.clock.now();
    return AppDataTable<DocumentInfo>(
      items: _controller.result.items,
      idOf: (d) => d.id,
      isLoading: _controller.isLoading,
      emptyTitle: 'Nessun documento',
      emptyIcon: Icons.folder_off_outlined,
      rowAccent: (d) => d.isPendingReview ? palette.warning : null,
      columns: [
        TableColumnDef(
          label: 'Documento',
          flex: 4,
          minWidth: 260,
          cell: (context, d) => Row(
            children: [
              Icon(fileIcon(d.extension), color: palette.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: CellText(d.title, secondary: d.fileName, bold: true),
              ),
            ],
          ),
        ),
        TableColumnDef(
          label: 'Categoria',
          flex: 2,
          minWidth: 150,
          cell: (context, d) => TagChip(d.category.label),
        ),
        TableColumnDef(
          label: 'Associato a',
          flex: 3,
          minWidth: 200,
          cell: (context, d) => InkWell(
            onTap: d.owner.type == DocumentOwnerType.centrale
                ? null
                : () => _openOwner(d),
            child: CellText(d.owner.label, secondary: d.owner.type.label),
          ),
        ),
        TableColumnDef(
          label: 'Origine',
          width: 140,
          cell: (context, d) => Text(d.source.label),
        ),
        TableColumnDef(
          label: 'Caricato',
          width: 190,
          cell: (context, d) => CellText(
            d.uploadedBy,
            secondary: Fmt.relative(d.uploadedAt, now),
          ),
        ),
        TableColumnDef(
          label: 'Dimensione',
          width: 100,
          alignEnd: true,
          cell: (context, d) => Text(Fmt.fileSize(d.sizeBytes)),
        ),
        TableColumnDef(
          label: 'Verifica',
          width: 150,
          cell: (context, d) {
            if (d.isPendingReview) {
              return Pill(
                label: 'Da verificare',
                style: severityStyle(context, NotificationSeverity.attenzione),
                dense: true,
              );
            }
            if (d.reviewedAt != null) {
              return Tooltip(
                message:
                    'Verificato da ${d.reviewedBy} il ${Fmt.dateTime(d.reviewedAt!)}',
                child: Pill(
                  label: 'Verificato',
                  style: changeRequestStatusStyle(
                    context,
                    ChangeRequestStatus.chiusa,
                  ),
                  dense: true,
                ),
              );
            }
            return Text('—', style: TextStyle(color: palette.textMuted));
          },
        ),
        TableColumnDef(
          label: '',
          width: 150,
          cell: (context, d) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: 44,
                child: d.isPendingReview
                    ? IconButton(
                        tooltip: 'Segna come verificato',
                        onPressed: () async {
                          if (await DocumentActions.markReviewed(context, d)) {
                            await _controller.refresh();
                          }
                        },
                        icon: Icon(
                          Icons.fact_check_outlined,
                          color: palette.warning,
                        ),
                      )
                    : null,
              ),
              SizedBox(
                width: 44,
                child: IconButton(
                  tooltip: 'Scarica',
                  onPressed: () => unawaited(downloadDocument(context, d)),
                  icon: const Icon(Icons.download_outlined),
                ),
              ),
              SizedBox(
                width: 44,
                child: d.source == DocumentSource.centrale
                    ? IconButton(
                        tooltip: 'Elimina',
                        onPressed: () async {
                          if (await DocumentActions.delete(context, d)) {
                            await _controller.refresh();
                          }
                        },
                        icon: Icon(Icons.delete_outline, color: palette.danger),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Scelta dell'elemento a cui associare nuovi documenti.
class _OwnerPickerDialog extends StatefulWidget {
  const _OwnerPickerDialog();

  @override
  State<_OwnerPickerDialog> createState() => _OwnerPickerDialogState();
}

class _OwnerPickerDialogState extends State<_OwnerPickerDialog> {
  DocumentOwnerType _type = DocumentOwnerType.centrale;
  DocumentOwner? _owner = const DocumentOwner.centrale();
  List<Service> _services = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _searchServices(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (text.trim().length < 2) {
        setState(() => _services = const []);
        return;
      }
      try {
        final result = await context.deps.repositories.services.searchServices(
          ServiceQuery(search: text, descending: true),
          page: const PageRequest(pageSize: 8),
        );
        if (mounted) setState(() => _services = result.items);
      } on RepositoryException {
        if (mounted) setState(() => _services = const []);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return AppDialog(
      title: 'Carica documenti',
      subtitle: 'A cosa vanno associati i documenti?',
      icon: Icons.upload_file_outlined,
      width: 620,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _owner == null
              ? null
              : () => Navigator.of(context).pop(_owner),
          icon: const Icon(Icons.attach_file, size: 18),
          label: const Text('Scegli i file…'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<DocumentOwnerType>(
            showSelectedIcon: false,
            segments: [
              for (final type in DocumentOwnerType.values)
                ButtonSegment(value: type, label: Text(type.label)),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() {
              _type = value.first;
              _owner = _type == DocumentOwnerType.centrale
                  ? const DocumentOwner.centrale()
                  : null;
            }),
          ),
          const SizedBox(height: 16),
          switch (_type) {
            DocumentOwnerType.centrale => Text(
              'Procedure, circolari e documenti di servizio della Centrale '
              'Operativa, visibili a tutti gli utenti.',
              style: TextStyle(color: palette.textSecondary),
            ),
            DocumentOwnerType.operatore => DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Operatore'),
              items: [
                for (final operator in deps.reference.operators)
                  DropdownMenuItem(
                    value: operator.id,
                    child: Text('${operator.sortName} · ${operator.code}'),
                  ),
              ],
              onChanged: (id) {
                final operator = deps.reference.operator(id);
                setState(
                  () => _owner = operator == null
                      ? null
                      : DocumentOwner(
                          type: DocumentOwnerType.operatore,
                          id: operator.id,
                          label: operator.fullName,
                        ),
                );
              },
            ),
            DocumentOwnerType.paziente => Autocomplete<Patient>(
              displayStringForOption: (p) => '${p.fullName} (${p.code})',
              optionsBuilder: (value) async {
                if (value.text.trim().length < 2) {
                  return const Iterable<Patient>.empty();
                }
                return deps.repositories.patients.searchPatients(value.text);
              },
              onSelected: (patient) => setState(
                () => _owner = DocumentOwner(
                  type: DocumentOwnerType.paziente,
                  id: patient.id,
                  label: patient.fullName,
                ),
              ),
              fieldViewBuilder: (context, controller, focus, submit) =>
                  TextField(
                    controller: controller,
                    focusNode: focus,
                    decoration: const InputDecoration(
                      labelText: 'Cerca paziente',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
            ),
            DocumentOwnerType.servizio => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  autofocus: true,
                  onChanged: _searchServices,
                  decoration: const InputDecoration(
                    labelText: 'Cerca servizio (codice o paziente)',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _owner?.id,
                  onChanged: (id) {
                    final service = _services
                        .where((s) => s.id == id)
                        .firstOrNull;
                    if (service == null) return;
                    setState(
                      () => _owner = DocumentOwner(
                        type: DocumentOwnerType.servizio,
                        id: service.id,
                        label: '${service.code} - ${service.patient.fullName}',
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      for (final service in _services)
                        RadioListTile<String>(
                          value: service.id,
                          title: Text(
                            '${service.code} · ${service.patient.fullName}',
                          ),
                          subtitle: Text(
                            '${service.kind.label} · ${Fmt.slot(service.scheduledStart, service.scheduledEnd)}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          },
          if (_owner != null && _type != DocumentOwnerType.centrale) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: palette.success),
                const SizedBox(width: 6),
                Expanded(child: Text('Selezionato: ${_owner!.label}')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
