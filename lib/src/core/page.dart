import 'json_reading.dart';

/// Fetches the page addressed by [query], re-running the same list call the
/// current page came from with updated pagination parameters.
typedef MuxPageFetcher<T> = Future<MuxPage<T>> Function(
  Map<String, Object?> query,
);

/// One page of a Mux list endpoint.
///
/// The four concrete shapes mirror the page classes of `@mux/ts`; generated
/// `list()` methods construct them from the raw response envelope and hand
/// back a fetcher for the next page. Iterate everything with [autoPaging].
abstract base class MuxPage<T> {
  /// Creates a page holding [data].
  const MuxPage(this.data);

  /// The items this page carried.
  final List<T> data;

  /// Whether asking for [nextPage] makes sense.
  ///
  /// For the page-numbered shapes this is optimistic, exactly as upstream: a
  /// non-empty page may be followed by more, and only fetching the next page
  /// (which comes back empty) settles it.
  bool get hasNextPage;

  /// Fetches the following page. Throws a [StateError] when [hasNextPage] is
  /// `false`.
  Future<MuxPage<T>> nextPage();

  /// Lazily walks every item across every page, fetching each next page only
  /// once the current one is exhausted.
  Stream<T> autoPaging() async* {
    MuxPage<T> page = this;
    while (true) {
      for (final item in page.data) {
        yield item;
      }
      if (!page.hasNextPage) {
        return;
      }
      page = await page.nextPage();
    }
  }
}

Never _noNextPage() => throw StateError(
      'No next page expected; please check `hasNextPage` before calling '
      '`nextPage()`.',
    );

/// `{ "data": [...] }`, paginated with `page` / `limit` query parameters.
///
/// The response carries no total, so the next page is requested as
/// `page + 1` until one comes back empty.
final class MuxBasePage<T> extends MuxPage<T> {
  /// Creates a page from already-decoded [data].
  const MuxBasePage({
    required List<T> data,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
  })  : _query = query,
        _fetchPage = fetchPage,
        super(data);

  /// Decodes a list response [envelope], applying [itemFromJson] to every
  /// element of `data`. [query] is the query the page was requested with and
  /// [fetchPage] re-issues the request for another query.
  factory MuxBasePage.fromEnvelope(
    Map<String, Object?> envelope, {
    required T Function(Map<String, Object?>) itemFromJson,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
    String objectName = 'MuxBasePage',
  }) =>
      MuxBasePage<T>(
        data: envelope.optObjectList('data', itemFromJson,
            objectName: objectName),
        query: query,
        fetchPage: fetchPage,
      );

  final Map<String, Object?> _query;
  final MuxPageFetcher<T> _fetchPage;

  @override
  bool get hasNextPage => data.isNotEmpty;

  @override
  Future<MuxPage<T>> nextPage() {
    if (!hasNextPage) {
      _noNextPage();
    }
    return _fetchPage({..._query, 'page': _currentPage(_query) + 1});
  }
}

/// `{ "data": [...], "total_row_count": n, "timeframe": [from, to], "limit": n }`,
/// the Mux Data list shape.
///
/// Like upstream, [totalRowCount] is surfaced but not used to decide
/// [hasNextPage]: the next page is requested as `page + 1` until one comes
/// back empty.
final class MuxPageWithTotal<T> extends MuxPage<T> {
  /// Creates a page from already-decoded values.
  const MuxPageWithTotal({
    required List<T> data,
    required this.totalRowCount,
    required this.timeframe,
    required this.limit,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
  })  : _query = query,
        _fetchPage = fetchPage,
        super(data);

  /// Decodes a list response [envelope]; see [MuxBasePage.fromEnvelope].
  factory MuxPageWithTotal.fromEnvelope(
    Map<String, Object?> envelope, {
    required T Function(Map<String, Object?>) itemFromJson,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
    String objectName = 'MuxPageWithTotal',
  }) =>
      MuxPageWithTotal<T>(
        data: envelope.optObjectList('data', itemFromJson,
            objectName: objectName),
        totalRowCount: envelope.optInt('total_row_count') ?? 0,
        timeframe: envelope.optIntList('timeframe'),
        limit: envelope.optInt('limit') ?? 0,
        query: query,
        fetchPage: fetchPage,
      );

  /// The total number of rows matching the query, across all pages.
  final int totalRowCount;

  /// The `[from, to]` unix-second window the results cover.
  final List<int> timeframe;

  /// The page size the server applied.
  final int limit;

  final Map<String, Object?> _query;
  final MuxPageFetcher<T> _fetchPage;

  @override
  bool get hasNextPage => data.isNotEmpty;

  @override
  Future<MuxPage<T>> nextPage() {
    if (!hasNextPage) {
      _noNextPage();
    }
    return _fetchPage({..._query, 'page': _currentPage(_query) + 1});
  }
}

/// `{ "data": [...], "timeframe": [from, to], "page": n, "limit": n }`, the
/// delivery-usage list shape.
///
/// The next page is `page + 1` where `page` is the number the *server*
/// reported, not the one that was requested.
final class MuxPageWithTimeframe<T> extends MuxPage<T> {
  /// Creates a page from already-decoded values.
  const MuxPageWithTimeframe({
    required List<T> data,
    required this.timeframe,
    required this.page,
    required this.limit,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
  })  : _query = query,
        _fetchPage = fetchPage,
        super(data);

  /// Decodes a list response [envelope]; see [MuxBasePage.fromEnvelope].
  factory MuxPageWithTimeframe.fromEnvelope(
    Map<String, Object?> envelope, {
    required T Function(Map<String, Object?>) itemFromJson,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
    String objectName = 'MuxPageWithTimeframe',
  }) =>
      MuxPageWithTimeframe<T>(
        data: envelope.optObjectList('data', itemFromJson,
            objectName: objectName),
        timeframe: envelope.optIntList('timeframe'),
        page: envelope.optInt('page') ?? 0,
        limit: envelope.optInt('limit') ?? 0,
        query: query,
        fetchPage: fetchPage,
      );

  /// The `[from, to]` unix-second window the results cover.
  final List<int> timeframe;

  /// The page number the server reported for this response.
  final int page;

  /// The page size the server applied.
  final int limit;

  final Map<String, Object?> _query;
  final MuxPageFetcher<T> _fetchPage;

  @override
  bool get hasNextPage => data.isNotEmpty;

  @override
  Future<MuxPage<T>> nextPage() {
    if (!hasNextPage) {
      _noNextPage();
    }
    return _fetchPage({..._query, 'page': page + 1});
  }
}

/// `{ "data": [...], "next_cursor": "..." }`, the shape of
/// `video.assets.list`.
///
/// The next page is requested with `cursor` set to [nextCursor]; an empty
/// or missing cursor means this was the last page.
final class MuxCursorPage<T> extends MuxPage<T> {
  /// Creates a page from already-decoded values.
  const MuxCursorPage({
    required List<T> data,
    required this.nextCursor,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
  })  : _query = query,
        _fetchPage = fetchPage,
        super(data);

  /// Decodes a list response [envelope]; see [MuxBasePage.fromEnvelope].
  factory MuxCursorPage.fromEnvelope(
    Map<String, Object?> envelope, {
    required T Function(Map<String, Object?>) itemFromJson,
    required Map<String, Object?> query,
    required MuxPageFetcher<T> fetchPage,
    String objectName = 'MuxCursorPage',
  }) {
    final cursor = envelope.optString('next_cursor');
    return MuxCursorPage<T>(
      data:
          envelope.optObjectList('data', itemFromJson, objectName: objectName),
      nextCursor: cursor == null || cursor.isEmpty ? null : cursor,
      query: query,
      fetchPage: fetchPage,
    );
  }

  /// The cursor addressing the following page, or `null` on the last page.
  final String? nextCursor;

  final Map<String, Object?> _query;
  final MuxPageFetcher<T> _fetchPage;

  @override
  bool get hasNextPage => data.isNotEmpty && nextCursor != null;

  @override
  Future<MuxPage<T>> nextPage() {
    final cursor = nextCursor;
    if (!hasNextPage || cursor == null) {
      _noNextPage();
    }
    return _fetchPage({..._query, 'cursor': cursor});
  }
}

int _currentPage(Map<String, Object?> query) {
  final page = query['page'];
  return page is int ? page : 1;
}
