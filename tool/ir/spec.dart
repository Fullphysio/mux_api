import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

typedef JsonMap = Map<String, Object?>;

final class OpenApiSpec {
  OpenApiSpec(this.root);

  factory OpenApiSpec.load(String path) =>
      OpenApiSpec(json.decode(File(path).readAsStringSync()) as JsonMap);

  final JsonMap root;

  JsonMap get schemas =>
      (root['components']! as JsonMap)['schemas']! as JsonMap;
  JsonMap get parameters =>
      (root['components']! as JsonMap)['parameters']! as JsonMap;
  JsonMap get paths => root['paths']! as JsonMap;
  JsonMap get webhooks => root['webhooks']! as JsonMap;

  String? refName(JsonMap node) {
    final ref = node[r'$ref'];
    if (ref is! String) return null;
    const prefix = '#/components/schemas/';
    if (!ref.startsWith(prefix)) throw StateError('unsupported \$ref $ref');
    return ref.substring(prefix.length);
  }

  JsonMap schema(String name) {
    final node = schemas[name];
    if (node == null) throw StateError('unknown schema $name');
    return node as JsonMap;
  }

  JsonMap parameter(JsonMap node) {
    final ref = node[r'$ref'];
    if (ref is! String) return node;
    const prefix = '#/components/parameters/';
    if (!ref.startsWith(prefix)) {
      throw StateError('unsupported parameter \$ref $ref');
    }
    final target = parameters[ref.substring(prefix.length)];
    if (target == null) throw StateError('unknown parameter $ref');
    return target as JsonMap;
  }

  JsonMap deref(JsonMap node) {
    var current = node;
    for (var i = 0; i < 10; i++) {
      final name = refName(current);
      if (name == null) return current;
      current = schema(name);
    }
    throw StateError('\$ref chain too deep at $node');
  }
}

final class OperationMapping {
  const OperationMapping(
      {required this.namespace, required this.method, this.page});
  final List<String> namespace;
  final String method;
  final String? page;
}

final class OperationMap {
  OperationMap(
      {required this.operations,
      required this.excluded,
      required this.muxTsTag});

  factory OperationMap.load(String path) {
    final doc = loadYaml(File(path).readAsStringSync()) as YamlMap;
    final operations = <String, OperationMapping>{};
    for (final entry in (doc['operations'] as YamlMap).entries) {
      final value = entry.value as YamlMap;
      operations[entry.key as String] = OperationMapping(
        namespace: (value['namespace'] as String).split('.'),
        method: value['method'] as String,
        page: value['page'] as String?,
      );
    }
    final excluded = <String>{
      for (final item in doc['exclude'] as YamlList)
        (item as YamlMap)['operation'] as String,
    };
    return OperationMap(
      operations: operations,
      excluded: excluded,
      muxTsTag: (doc['spec'] as YamlMap)['muxTsTag'] as String,
    );
  }

  final Map<String, OperationMapping> operations;
  final Set<String> excluded;
  final String muxTsTag;
}

final class UnionNames {
  UnionNames(this.byStructure);

  factory UnionNames.load(String path) {
    final file = File(path);
    if (!file.existsSync()) return UnionNames(const {});
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    final result = <String, String>{};
    for (final item in (doc['inlineUnions'] as YamlList?) ?? YamlList()) {
      final map = item as YamlMap;
      final variants = (map['variants'] as YamlList).cast<String>().toList()
        ..sort();
      result['${map['discriminator']}|${variants.join(',')}'] =
          map['name'] as String;
    }
    return UnionNames(result);
  }

  final Map<String, String> byStructure;
}
