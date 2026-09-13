import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mux_api/src/core/client.dart';
import 'package:mux_api/src/core/transport.dart';
import 'package:test/test.dart';

void main() {
  test('requestJson returns the envelope for the caller to unwrap', () async {
    http.Request? captured;
    final client = MuxClient(
      tokenId: 'id',
      tokenSecret: 'secret',
      maxRetries: 0,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"data":{"id":"u1"}}', 200);
      }),
    );
    final envelope = await client.requestJson(
      method: 'GET',
      path: '/video/v1/uploads/u1',
    );
    expect(envelope, {
      'data': {'id': 'u1'}
    });
    expect(captured!.headers['authorization'], 'Basic aWQ6c2VjcmV0');
    expect(captured!.headers['accept'], 'application/json');
  });

  test('accept and host are forwarded', () async {
    http.Request? captured;
    final client = MuxClient(
      tokenId: 'id',
      tokenSecret: 'secret',
      maxRetries: 0,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response.bytes([0], 200);
      }),
    );
    await client.requestBytes(
      method: 'GET',
      path: '/pid/thumbnail.png',
      host: MuxHost.image,
      accept: 'application/binary',
    );
    expect(captured!.url.toString(), 'https://image.mux.com/pid/thumbnail.png');
    expect(captured!.headers['accept'], 'application/binary');
  });

  test('defaults match upstream', () {
    final client = MuxClient(tokenId: 'id', tokenSecret: 'secret');
    expect(client.timeout, const Duration(seconds: 60));
    expect(client.maxRetries, 2);
    expect(client.webhookSecret, isNull);
    client.close();
  });
}
