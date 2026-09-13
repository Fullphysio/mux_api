import 'package:mux_api/src/core/decode_exception.dart';
import 'package:mux_api/src/core/page.dart';
import 'package:mux_api/src/core/query_encoding.dart';
import 'package:test/test.dart';

import '../_support/fixtures.dart';

typedef _Item = Map<String, Object?>;

_Item _identity(Map<String, Object?> json) => json;

void main() {
  group('auto-pagination matches @mux/ts 15.1.0', () {
    for (final testCase in casesOf(loadFixture('pagination_golden'))) {
      final kind = testCase['page']! as String;
      final input = mapOf(testCase['input']);
      final path = input['path']! as String;
      final initialQuery = mapOf(input['query']);
      final responses = (testCase['responses']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final firstPage = mapOf(testCase['firstPage']);

      test(testCase['name']! as String, () async {
        final requests = <String>[];
        var index = 0;

        String urlFor(Map<String, Object?> query) {
          final encoded = muxQueryEncode(query);
          return 'https://api.mux.com$path${encoded.isEmpty ? '' : '?$encoded'}';
        }

        late MuxPage<_Item> Function(Map<String, Object?>, Map<String, Object?>)
            build;

        Future<MuxPage<_Item>> fetch(Map<String, Object?> query) async {
          requests.add(urlFor(query));
          return build(responses[index++], query);
        }

        build = switch (kind) {
          'base' => (envelope, query) => MuxBasePage<_Item>.fromEnvelope(
                envelope,
                itemFromJson: _identity,
                query: query,
                fetchPage: fetch,
              ),
          'cursor' => (envelope, query) => MuxCursorPage<_Item>.fromEnvelope(
                envelope,
                itemFromJson: _identity,
                query: query,
                fetchPage: fetch,
              ),
          'withTimeframe' => (envelope, query) =>
              MuxPageWithTimeframe<_Item>.fromEnvelope(
                envelope,
                itemFromJson: _identity,
                query: query,
                fetchPage: fetch,
              ),
          _ => throw StateError('unknown page kind $kind'),
        };

        final first = await fetch(initialQuery);
        expect(first.hasNextPage, firstPage['hasNextPage']);
        expect(
          first.data.map((item) => item['id']).toList(),
          firstPage['dataIds'],
        );
        if (first is MuxCursorPage<_Item>) {
          final cursor = firstPage['nextCursor'] as String?;
          expect(first.nextCursor,
              cursor == null || cursor.isEmpty ? null : cursor);
        }
        if (first is MuxPageWithTimeframe<_Item>) {
          expect(first.page, firstPage['pageNumber']);
          expect(first.limit, firstPage['limit']);
          expect(first.timeframe, firstPage['timeframe']);
        }

        final ids = await first.autoPaging().map((item) => item['id']).toList();
        expect(ids, testCase['autoPagedIds']);
        expect(requests, testCase['requests']);
      });
    }
  });

  group('MuxPage', () {
    Future<MuxPage<_Item>> neverFetch(Map<String, Object?> query) =>
        throw StateError('should not fetch');

    test('nextPage throws when there is no next page', () {
      final page = MuxBasePage<_Item>.fromEnvelope(
        {'data': <Object?>[]},
        itemFromJson: _identity,
        query: const {},
        fetchPage: neverFetch,
      );
      expect(page.hasNextPage, isFalse);
      expect(page.nextPage, throwsStateError);
    });

    test(
        'MuxPageWithTotal surfaces its extra fields but ignores them for '
        'paging, as upstream', () {
      final page = MuxPageWithTotal<_Item>.fromEnvelope(
        {
          'data': [
            {'id': 'a'}
          ],
          'total_row_count': 1,
          'timeframe': [1, 2],
          'limit': 100,
        },
        itemFromJson: _identity,
        query: const {'limit': 100},
        fetchPage: neverFetch,
      );
      expect(page.totalRowCount, 1);
      expect(page.timeframe, [1, 2]);
      expect(page.limit, 100);
      expect(page.hasNextPage, isTrue);
    });

    test('missing envelope fields decode to empty defaults', () {
      final page = MuxPageWithTotal<_Item>.fromEnvelope(
        const {},
        itemFromJson: _identity,
        query: const {},
        fetchPage: neverFetch,
      );
      expect(page.data, isEmpty);
      expect(page.totalRowCount, 0);
      expect(page.timeframe, isEmpty);
      expect(page.limit, 0);
    });

    test('a non-object element in data is a decode failure', () {
      expect(
        () => MuxBasePage<_Item>.fromEnvelope(
          {
            'data': <Object?>['not an object']
          },
          itemFromJson: _identity,
          query: const {},
          fetchPage: neverFetch,
        ),
        throwsA(isA<MuxDecodeException>()),
      );
    });
  });
}
