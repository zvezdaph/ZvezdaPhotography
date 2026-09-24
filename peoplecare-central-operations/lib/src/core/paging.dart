/// Richiesta di una pagina di risultati (pagine numerate da 1).
class PageRequest {
  const PageRequest({this.page = 1, this.pageSize = 50})
    : assert(page >= 1),
      assert(pageSize >= 1);

  final int page;
  final int pageSize;

  int get offset => (page - 1) * pageSize;

  PageRequest copyWith({int? page, int? pageSize}) =>
      PageRequest(page: page ?? this.page, pageSize: pageSize ?? this.pageSize);
}

/// Una pagina di risultati con il totale complessivo.
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory PagedResult.fromAll(List<T> all, PageRequest request) {
    final start = request.offset.clamp(0, all.length);
    final end = (start + request.pageSize).clamp(0, all.length);
    return PagedResult(
      items: List<T>.unmodifiable(all.sublist(start, end)),
      total: all.length,
      page: request.page,
      pageSize: request.pageSize,
    );
  }

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  int get pageCount => total == 0 ? 1 : ((total - 1) ~/ pageSize) + 1;
  bool get hasPrevious => page > 1;
  bool get hasNext => page < pageCount;
  int get firstIndex => total == 0 ? 0 : (page - 1) * pageSize + 1;
  int get lastIndex => (firstIndex == 0) ? 0 : firstIndex + items.length - 1;
}

/// Legge tutte le pagine di una ricerca (es. esportazioni CSV) a blocchi di
/// [pageSize], fermandosi al `total` dichiarato o a [maxItems].
Future<List<T>> fetchAllPages<T>(
  Future<PagedResult<T>> Function(PageRequest page) fetch, {
  int pageSize = 500,
  int maxItems = 50000,
}) async {
  final items = <T>[];
  for (var page = 1; ; page++) {
    final result = await fetch(PageRequest(page: page, pageSize: pageSize));
    items.addAll(result.items);
    if (result.items.isEmpty ||
        !result.hasNext ||
        items.length >= result.total ||
        items.length >= maxItems) {
      break;
    }
  }
  return items.length > maxItems ? items.sublist(0, maxItems) : items;
}
