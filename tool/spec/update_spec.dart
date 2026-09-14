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

  final previousSpec = File('tool/spec/mux-openapi.json');
  final previousTag = File('tool/spec/SPEC_VERSION');
  if (previousSpec.existsSync() && previousTag.existsSync()) {
    final previous =
        json.decode(previousSpec.readAsStringSync()) as Map<String, Object?>;
    File('tool/spec/CHANGELOG_SPEC.md').writeAsStringSync(
      _changelog(previous, decoded, previousTag.readAsStringSync().trim(), tag),
    );
  }

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

Set<String> _operations(Map<String, Object?> spec) => {
      for (final entry in (spec['paths']! as Map<String, Object?>).entries)
        for (final method in (entry.value as Map<String, Object?>).keys)
          if (_httpMethods.contains(method))
            '${method.toUpperCase()} ${entry.key}',
    };

Map<String, Object?> _schemas(Map<String, Object?> spec) =>
    (spec['components']! as Map<String, Object?>)['schemas']!
        as Map<String, Object?>;

Map<String, List<String>> _enumValues(Map<String, Object?> spec) {
  final result = <String, List<String>>{};
  void walk(Object? node, String path) {
    if (node is! Map<String, Object?>) return;
    final values = node['enum'];
    if (values is List) {
      result[path] = values.map((value) => '$value').toList();
    }
    final properties = node['properties'];
    if (properties is Map<String, Object?>) {
      for (final entry in properties.entries) {
        walk(entry.value, '$path.${entry.key}');
      }
    }
    walk(node['items'], '$path[]');
    for (final key in const ['allOf', 'oneOf', 'anyOf']) {
      final parts = node[key];
      if (parts is List) {
        for (var i = 0; i < parts.length; i++) {
          walk(parts[i], '$path<$key $i>');
        }
      }
    }
  }

  for (final entry in _schemas(spec).entries) {
    walk(entry.value, entry.key);
  }
  return result;
}

Map<String, Set<String>> _required(Map<String, Object?> spec) => {
      for (final entry in _schemas(spec).entries)
        entry.key: ((entry.value as Map<String, Object?>)['required'] as List?)
                ?.cast<String>()
                .toSet() ??
            const {},
    };

String _changelog(Map<String, Object?> previous, Map<String, Object?> next,
    String fromTag, String toTag) {
  final buffer =
      StringBuffer('# Mux OpenAPI specification: $fromTag → $toTag\n');
  var sections = 0;
  void section(String title, Iterable<String> added, Iterable<String> removed) {
    final sortedAdded = added.toList()..sort();
    final sortedRemoved = removed.toList()..sort();
    if (sortedAdded.isEmpty && sortedRemoved.isEmpty) return;
    sections++;
    buffer.writeln('\n## $title\n');
    for (final item in sortedAdded) {
      buffer.writeln('- added `$item`');
    }
    for (final item in sortedRemoved) {
      buffer.writeln('- removed `$item`');
    }
  }

  final oldOps = _operations(previous);
  final newOps = _operations(next);
  section('Operations', newOps.difference(oldOps), oldOps.difference(newOps));
  final oldSchemas = _schemas(previous).keys.toSet();
  final newSchemas = _schemas(next).keys.toSet();
  section('Schemas', newSchemas.difference(oldSchemas),
      oldSchemas.difference(newSchemas));
  final oldWebhooks =
      (previous['webhooks']! as Map).keys.cast<String>().toSet();
  final newWebhooks = (next['webhooks']! as Map).keys.cast<String>().toSet();
  section('Webhooks', newWebhooks.difference(oldWebhooks),
      oldWebhooks.difference(newWebhooks));
  final oldEnums = _enumValues(previous);
  final newEnums = _enumValues(next);
  final enumAdded = <String>[];
  final enumRemoved = <String>[];
  for (final path in {...oldEnums.keys, ...newEnums.keys}) {
    final before = (oldEnums[path] ?? const <String>[]).toSet();
    final after = (newEnums[path] ?? const <String>[]).toSet();
    enumAdded.addAll(after.difference(before).map((value) => '$path = $value'));
    enumRemoved
        .addAll(before.difference(after).map((value) => '$path = $value'));
  }
  section('Enum values', enumAdded, enumRemoved);
  final oldRequired = _required(previous);
  final newRequired = _required(next);
  final requiredAdded = <String>[];
  final requiredRemoved = <String>[];
  for (final schema in newSchemas.intersection(oldSchemas)) {
    requiredAdded.addAll(newRequired[schema]!
        .difference(oldRequired[schema]!)
        .map((field) => '$schema.$field'));
    requiredRemoved.addAll(oldRequired[schema]!
        .difference(newRequired[schema]!)
        .map((field) => '$schema.$field'));
  }
  section('Required fields', requiredAdded, requiredRemoved);
  if (sections == 0) {
    buffer.writeln(
        '\nNo change to operations, schemas, webhooks, enum values or required fields.');
  }
  return buffer.toString();
}

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
