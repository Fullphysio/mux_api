import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Vendors the Mux OpenAPI specification a `muxinc/mux-ts` release was
/// generated from into `tool/spec/`, recording its digest and the tag.
///
/// Usage: `dart run tool/spec/update_spec.dart --tag v15.1.0`
///
/// Mux does not publish its specification on its own; the only public copy
/// is the one Stainless embeds, base64-encoded and gzipped, in the mock-server
/// script of each SDK release. The tag is never chosen automatically — pick
/// the `@mux/ts` release this package tracks and pass it explicitly.
Future<void> main(List<String> arguments) async {
  final tag = _parseTag(arguments);
  final url = Uri.parse(
    'https://raw.githubusercontent.com/muxinc/mux-ts/$tag/scripts/mock',
  );

  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to download scripts/mock for tag "$tag" from $url: '
      'HTTP ${response.statusCode}. Confirm the tag exists in '
      'https://github.com/muxinc/mux-ts/tags.',
    );
  }

  final embedded = RegExp(r'^\s*EMBEDDED_SPEC="([^"]+)"\s*$', multiLine: true)
      .firstMatch(response.body);
  if (embedded == null) {
    throw StateError(
      'scripts/mock at tag "$tag" carries no EMBEDDED_SPEC; the release may '
      'have moved the specification elsewhere.',
    );
  }

  final bytes = gzip.decode(base64.decode(embedded.group(1)!));
  final decoded = json.decode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw StateError('The embedded specification is not a JSON object.');
  }
  for (final key in const ['openapi', 'paths', 'components', 'webhooks']) {
    final value = decoded[key];
    if (value == null || (value is Map && value.isEmpty)) {
      throw StateError(
        'The embedded specification has no "$key" section; refusing to vendor.',
      );
    }
  }

  final canonical =
      '${const JsonEncoder.withIndent('  ').convert(_sortKeys(decoded))}\n';
  final digest = sha256.convert(utf8.encode(canonical)).toString();

  File('tool/spec/mux-openapi.json').writeAsStringSync(canonical);
  File('tool/spec/SPEC_SHA256').writeAsStringSync('$digest\n');
  File('tool/spec/SPEC_VERSION').writeAsStringSync('$tag\n');

  final paths = decoded['paths']! as Map<String, Object?>;
  final operations = paths.values
      .whereType<Map<String, Object?>>()
      .expand((item) => item.keys.where(_httpMethods.contains))
      .length;
  stdout.writeln(
    'Vendored tool/spec/mux-openapi.json at $tag: ${paths.length} paths, '
    '$operations operations, '
    '${(decoded['components']! as Map<String, Object?>)['schemas'] is Map ? ((decoded['components']! as Map<String, Object?>)['schemas']! as Map).length : 0} schemas, '
    '${(decoded['webhooks']! as Map).length} webhooks ($digest).',
  );
}

const Set<String> _httpMethods = {'get', 'post', 'put', 'patch', 'delete'};

String _parseTag(List<String> arguments) {
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--tag') {
      if (i + 1 >= arguments.length) {
        throw ArgumentError('--tag requires a value, e.g. --tag v15.1.0.');
      }
      return arguments[i + 1];
    }
    if (argument.startsWith('--tag=')) {
      return argument.substring('--tag='.length);
    }
  }
  throw ArgumentError(
    'Usage: dart run tool/spec/update_spec.dart --tag vX.Y.Z\n'
    'Pass the muxinc/mux-ts release tag to track explicitly. This script '
    'never picks a tag on its own.',
  );
}

Object? _sortKeys(Object? value) {
  if (value is Map<String, Object?>) {
    return SplayTreeMap<String, Object?>.fromIterables(
      value.keys.toList()..sort(),
      (value.keys.toList()..sort()).map((key) => _sortKeys(value[key])),
    );
  }
  if (value is List<Object?>) {
    return value.map(_sortKeys).toList(growable: false);
  }
  return value;
}
