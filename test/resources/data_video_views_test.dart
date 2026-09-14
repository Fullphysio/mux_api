import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mux_api/mux_api.dart';
import 'package:test/test.dart';

void main() {
  group('array query parameters', () {
    test(
        'a spec name already ending in [] is sent with a single bracket pair, '
        'not the [][] that @mux/ts 15.1.0 emits and Mux rejects', () async {
      late Uri requested;
      final client = MuxClient(
        tokenId: 'id',
        tokenSecret: 'secret',
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response('{"data": []}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(client.close);

      await client.data.videoViews.list(
        limit: 1,
        timeframe: ['7:days'],
        filters: ['browser:Chrome', 'country:FR'],
      );

      expect(
        requested.query,
        'limit=1&filters%5B%5D=browser%3AChrome&filters%5B%5D=country%3AFR'
        '&timeframe%5B%5D=7%3Adays',
      );
    });
  });
}
