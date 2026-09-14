import 'dart:io';

import 'emit/emitters.dart';
import 'ir/model.dart';
import 'ir/resolve.dart';
import 'ir/spec.dart';

const List<String> _managedDirectories = [
  'lib/src/generated',
  'test/generated'
];

Future<void> main(List<String> arguments) async {
  final spec = OpenApiSpec.load('tool/spec/mux-openapi.json');
  final operations = OperationMap.load('tool/spec/resources.yaml');
  final unionNames = UnionNames.load('tool/spec/union_names.yaml');
  final ir = Resolver(spec, operations, unionNames).resolve();

  if (arguments.contains('--report')) {
    _report(ir);
    return;
  }

  final files = Emitter(ir).emitAll();
  final staging = Directory.systemTemp.createTempSync('mux_api_generate_');
  try {
    for (final file in files) {
      final target = File('${staging.path}/${file.path}')
        ..createSync(recursive: true);
      target.writeAsStringSync(file.content);
    }
    final format = await Process.run('dart',
        ['format', '--language-version=${_languageVersion()}', staging.path]);
    if (format.exitCode != 0) {
      stderr.writeln(format.stdout);
      stderr.writeln(format.stderr);
      throw StateError('dart format failed on the generated output');
    }
    final generated = <String, String>{
      for (final file in files)
        file.path: File('${staging.path}/${file.path}').readAsStringSync(),
    };

    if (arguments.contains('--check')) {
      final drift = _drift(generated);
      if (drift.isEmpty) {
        stdout.writeln(
            'Generated code is up to date (${generated.length} files).');
        return;
      }
      stderr.writeln('Generated code is out of date:');
      drift.forEach(stderr.writeln);
      exitCode = 1;
      return;
    }

    for (final directory in _managedDirectories) {
      final dir = Directory(directory);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    for (final entry in generated.entries) {
      File(entry.key)
        ..createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    stdout.writeln('Wrote ${generated.length} generated files.');
  } finally {
    staging.deleteSync(recursive: true);
  }
}

String _languageVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(r'''sdk:\s*['"]?\^(\d+\.\d+)''').firstMatch(pubspec);
  if (match == null) {
    throw StateError(
        'pubspec.yaml has no ^X.Y sdk constraint to derive the language version from');
  }
  return match.group(1)!;
}

List<String> _drift(Map<String, String> generated) {
  final drift = <String>[];
  final existing = <String>{};
  for (final directory in _managedDirectories) {
    final dir = Directory(directory);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true).whereType<File>()) {
      existing.add(entity.path);
    }
  }
  for (final entry in generated.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      drift.add('  missing: ${entry.key}');
    } else if (file.readAsStringSync() != entry.value) {
      drift.add('  changed: ${entry.key}');
    }
  }
  for (final path in existing) {
    if (!generated.containsKey(path)) drift.add('  stale:   $path');
  }
  return drift..sort();
}

void _report(GeneratorIr ir) {
  stdout.writeln(
      'classes: ${ir.classes.length} (params: ${ir.classes.values.where((c) => c.kind == ClassKind.params).length})');
  stdout.writeln('enums: ${ir.enums.length}');
  stdout.writeln('unions: ${ir.unions.length}');
  stdout.writeln('webhooks: ${ir.webhooks.length}');
  var operationCount = 0;
  void walk(NamespaceIr namespace, int depth) {
    operationCount += namespace.operations.length;
    stdout.writeln(
        '${'  ' * depth}${namespace.path.join('.')} -> ${namespace.className} (${namespace.operations.length} ops)');
    for (final child in namespace.children.values) {
      walk(child, depth + 1);
    }
  }

  for (final namespace in ir.namespaces.values) {
    walk(namespace, 0);
  }
  stdout.writeln('operations: $operationCount');
  stdout.writeln(
      'examples: ${ir.examples.values.fold<int>(0, (sum, list) => sum + list.length)} for ${ir.examples.length} classes');
  stdout.writeln('--- enums ---');
  for (final e in ir.enums.values) {
    stdout.writeln(
        '${e.enumName}: ${e.values.map((v) => v.dartName).join(', ')}');
  }
  stdout.writeln('--- unions ---');
  for (final u in ir.unions.values) {
    stdout.writeln(
        '${u.unionName} by ${u.discriminator}: ${u.variants.map((v) => '${v.wireValue}=${v.className}').join(', ')}');
  }
  stdout.writeln('--- classes ---');
  for (final c in ir.classes.values) {
    stdout.writeln(
        '${c.className}${c.superType == null ? '' : ' extends ${c.superType}'} [${c.kind.name}] ${c.fields.length} fields${c.origin == null ? '' : ' <- ${c.origin}'}');
  }
}
