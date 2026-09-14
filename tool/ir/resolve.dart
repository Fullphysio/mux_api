import 'model.dart';
import 'naming.dart';
import 'spec.dart';

const Set<String> _dartCoreNames = {
  'Type',
  'Object',
  'String',
  'List',
  'Map',
  'Function',
  'Error',
  'Exception',
  'Enum',
  'Iterable',
  'Set',
  'Duration',
  'DateTime',
  'Uri',
  'Symbol',
  'Null',
  'Record',
  'Future',
  'Stream',
  'Comparable',
  'Pattern',
  'Match',
  'Invocation',
};

const Set<String> _primitiveTypeNames = {
  'string',
  'integer',
  'number',
  'boolean'
};

final class Resolver {
  Resolver(this.spec, this.operationMap, this.unionNames);

  final OpenApiSpec spec;
  final OperationMap operationMap;
  final UnionNames unionNames;

  final Map<String, ClassIr> classes = {};
  final Map<String, EnumIr> enums = {};
  final Map<String, UnionIr> unions = {};
  final Map<String, IrType> _aliases = {};
  final Map<String, String> _namedKinds = {};
  final Map<String, String> _enumByKey = {};
  final Map<String, Set<String>> _tuplesByProp = {};
  final Map<String, String> _unionByStructure = {};
  final Map<String, JsonMap> _classSources = {};
  final Map<String, List<JsonMap>> examples = {};
  final Map<String, NamespaceIr> namespaces = {};
  final List<WebhookIr> webhooks = [];

  GeneratorIr resolve() {
    _collectOwnedEnums();
    _collectEnumTuples(spec.schemas);
    _collectEnumTuples(spec.paths);
    _collectEnumTuples(spec.webhooks);
    _resolveOperations();
    _resolveWebhooks();
    return GeneratorIr(
      classes: Map.fromEntries(
          classes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      enums: Map.fromEntries(
          enums.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      unions: Map.fromEntries(
          unions.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      namespaces: namespaces,
      webhooks: webhooks..sort((a, b) => a.eventType.compareTo(b.eventType)),
      examples: examples,
    );
  }

  final Map<String, Set<String>> _enumOwnersByKey = {};

  void _collectOwnedEnums() {
    for (final entry in spec.schemas.entries) {
      _walkForEnums(entry.value as JsonMap, owner: _className(entry.key));
    }
  }

  void _walkForEnums(JsonMap node, {required String owner}) {
    for (final part in [
      ...((node['allOf'] as List?) ?? const []),
      ...((node['oneOf'] as List?) ?? const [])
    ].cast<JsonMap>()) {
      if (!part.containsKey(r'$ref')) _walkForEnums(part, owner: owner);
    }
    final properties = node['properties'];
    if (properties is! JsonMap) return;
    for (final entry in properties.entries) {
      final prop = entry.key;
      final property = entry.value as JsonMap;
      _recordOwner(prop, property, owner);
      final items = property['items'];
      if (items is JsonMap) {
        _recordOwner(singular(prop), items, owner);
        if (!items.containsKey(r'$ref')) {
          _walkForEnums(items, owner: '$owner${pascalCase(singular(prop))}');
        }
      }
      if (!property.containsKey(r'$ref')) {
        _walkForEnums(property, owner: '$owner${pascalCase(prop)}');
      }
    }
  }

  void _recordOwner(String prop, JsonMap property, String owner) {
    final values = _stringEnumValues(property);
    if (values == null || values.length <= 1) return;
    _enumOwnersByKey
        .putIfAbsent('$prop|${_tupleKey(values)}', () => {})
        .add(owner);
  }

  void _collectEnumTuples(Object? node) {
    if (node is JsonMap) {
      final properties = node['properties'];
      if (properties is JsonMap) {
        for (final entry in properties.entries) {
          final property = entry.value;
          if (property is JsonMap) {
            _recordTuple(entry.key, property);
            final items = property['items'];
            if (items is JsonMap) _recordTuple(singular(entry.key), items);
          }
        }
      }
      for (final value in node.values) {
        _collectEnumTuples(value);
      }
    } else if (node is List) {
      for (final value in node) {
        _collectEnumTuples(value);
      }
    }
  }

  void _recordTuple(String prop, JsonMap property) {
    final values = _stringEnumValues(property);
    if (values == null || values.length <= 1) return;
    _tuplesByProp.putIfAbsent(prop, () => {}).add(_tupleKey(values));
  }

  List<String>? _stringEnumValues(JsonMap node) {
    final raw = node['enum'];
    if (raw is! List) return null;
    if (_typeName(node) != 'string') return null;
    return raw.whereType<String>().toList();
  }

  String _tupleKey(List<String> values) => (values.toList()..sort()).join('|');

  String? _typeName(JsonMap node) {
    final type = node['type'];
    if (type is String) return type;
    if (type is List) {
      final names =
          type.whereType<String>().where((name) => name != 'null').toList();
      if (names.length == 1) return names.single;
      if (names.isEmpty) return null;
      throw StateError('multi-typed schema is not supported: $type');
    }
    if (node.containsKey('properties')) return 'object';
    return null;
  }

  bool _isObject(JsonMap node) =>
      _typeName(node) == 'object' || node.containsKey('properties');

  String _docOf(JsonMap node) {
    final description = node['description'];
    return description is String ? description : '';
  }

  String _className(String raw) {
    final name = pascalCase(raw);
    return _dartCoreNames.contains(name) ? 'Mux$name' : name;
  }

  IrType _refType(String name) {
    _classifyNamed(name);
    switch (_namedKinds[name]) {
      case 'class':
        return IrRef(_className(name));
      case 'enum':
        return IrEnumRef(_className(name));
      case 'union':
        return IrUnionRef(_className(name));
      case 'alias':
        return _aliases[name]!;
      default:
        throw StateError('schema $name has no kind');
    }
  }

  void _classifyNamed(String name) {
    if (_namedKinds.containsKey(name)) return;
    final node = spec.schema(name);
    final className = _className(name);
    final refName = spec.refName(node);
    if (refName != null) {
      _namedKinds[name] = 'alias';
      _aliases[name] = _refType(refName);
      return;
    }
    if (_stringEnumValues(node) != null &&
        (_stringEnumValues(node)!.length > 1)) {
      _namedKinds[name] = 'enum';
      _registerEnum(className, node, _stringEnumValues(node)!,
          key: 'named:$name');
      return;
    }
    if (node.containsKey('oneOf') && node.containsKey('discriminator')) {
      _namedKinds[name] = 'union';
      _unionFrom(node, className);
      return;
    }
    if (node.containsKey('allOf')) {
      _namedKinds[name] = 'class';
      _classFrom(_flattenAllOf(node), className,
          kind: ClassKind.model, origin: name);
      _recordExample(className, node['example']);
      return;
    }
    if (_isObject(node)) {
      _namedKinds[name] = 'class';
      _classFrom(node, className, kind: ClassKind.model, origin: name);
      _recordExample(className, node['example']);
      return;
    }
    _namedKinds[name] = 'alias';
    _aliases[name] = _typeOf(node, owner: className, prop: name);
  }

  void _recordExample(String className, Object? example) {
    if (example is JsonMap) {
      examples.putIfAbsent(className, () => []).add(example);
    }
  }

  JsonMap _flattenAllOf(JsonMap node) {
    final properties = <String, Object?>{};
    final required = <String>{};
    String? description;
    var noRequired = false;
    for (final part in (node['allOf'] as List).cast<JsonMap>()) {
      var resolved = spec.deref(part);
      if (resolved.containsKey('allOf')) resolved = _flattenAllOf(resolved);
      final partProperties = resolved['properties'];
      if (partProperties is JsonMap) properties.addAll(partProperties);
      final partRequired = resolved['required'];
      if (partRequired is List) required.addAll(partRequired.cast<String>());
      description ??=
          (part['description'] ?? resolved['description']) as String?;
      if (resolved['x-mux-no-required-properties'] == true) noRequired = true;
    }
    return {
      'type': 'object',
      'properties': properties,
      'required': required.toList()..sort(),
      if (description != null) 'description': description,
      if (node['description'] != null) 'description': node['description'],
      if (noRequired) 'x-mux-no-required-properties': true,
    };
  }

  bool _isSubstantive(JsonMap part) =>
      part.containsKey(r'$ref') ||
      part.containsKey('type') ||
      part.containsKey('properties') ||
      part.containsKey('enum') ||
      part.containsKey('items') ||
      part.containsKey('oneOf') ||
      part.containsKey('allOf') ||
      part.containsKey('required');

  IrType _typeOf(JsonMap node, {required String owner, required String prop}) {
    final refName = spec.refName(node);
    if (refName != null) return _refType(refName);
    if (node.containsKey('allOf')) {
      final parts = (node['allOf'] as List)
          .cast<JsonMap>()
          .where(_isSubstantive)
          .toList();
      if (parts.length == 1 && !parts.single.containsKey('required')) {
        return _typeOf(parts.single, owner: owner, prop: prop);
      }
      return IrRef(_classFrom(_flattenAllOf(node), '$owner${pascalCase(prop)}',
              kind: ClassKind.model)
          .className);
    }
    if (node.containsKey('oneOf')) {
      return _oneOfType(node, owner: owner, prop: prop);
    }
    final type = _typeName(node);
    final enumValues = _stringEnumValues(node);
    if (enumValues != null) {
      if (enumValues.length <= 1 || node['x-stainless-const'] == true) {
        return const IrString();
      }
      return IrEnumRef(_inlineEnum(node, enumValues, owner: owner, prop: prop));
    }
    switch (type) {
      case 'string':
        return const IrString();
      case 'integer':
        return const IrInt();
      case 'number':
        return const IrDouble();
      case 'boolean':
        return const IrBool();
      case 'array':
        final items = node['items'];
        if (items is! JsonMap) return const IrList(IrJson());
        return IrList(_typeOf(items, owner: owner, prop: singular(prop)));
      case 'object':
        if (node.containsKey('properties')) {
          return _inlineObject(node, owner: owner, prop: prop);
        }
        final additional = node['additionalProperties'];
        if (additional is JsonMap && _typeName(additional) == 'string') {
          return const IrStringMap();
        }
        return const IrJsonMap();
      default:
        if (node.containsKey('properties')) {
          return _inlineObject(node, owner: owner, prop: prop);
        }
        return const IrJson();
    }
  }

  final Map<String, String> _inlineByStructure = {};
  Map<String, String>? _namedByStructure;

  IrType _inlineObject(JsonMap node,
      {required String owner, required String prop}) {
    final candidate = '$owner${pascalCase(prop)}';
    final sameName = spec.schemas.keys
        .where((name) => _className(name) == _className(candidate))
        .toList();
    if (sameName.isNotEmpty &&
        _similarShape(spec.schema(sameName.first), node)) {
      return _refType(sameName.first);
    }
    final structure = _structure(node);
    _namedByStructure ??= {
      for (final entry in spec.schemas.entries)
        if (_isObject(entry.value as JsonMap) &&
            !(entry.value as JsonMap).containsKey('oneOf'))
          _structure(entry.value as JsonMap): entry.key,
    };
    final namedTwin = _namedByStructure![structure];
    if (namedTwin != null && _namedKinds[namedTwin] != 'alias') {
      return _refType(namedTwin);
    }
    final inlineTwin = _inlineByStructure[structure];
    if (inlineTwin != null) return IrRef(inlineTwin);
    final name = sameName.isEmpty ? candidate : '${candidate}Inline';
    final className = _classFrom(node, name, kind: ClassKind.model).className;
    _inlineByStructure[structure] = className;
    return IrRef(className);
  }

  static const Set<String> _cosmeticKeys = {
    'description',
    'title',
    'example',
    'examples',
    'default',
    'minLength',
    'maxLength',
    'minimum',
    'maximum',
    'minItems',
    'maxItems',
    'nullable',
    'deprecated',
    'readOnly',
    'writeOnly',
    'pattern',
    'uniqueItems',
  };

  String _structure(Object? node) {
    if (node is JsonMap) {
      final keys = node.keys
          .where((key) => !_cosmeticKeys.contains(key) && !key.startsWith('x-'))
          .toList()
        ..sort();
      return '{${keys.map((key) => '"$key":${_structure(node[key])}').join(',')}}';
    }
    if (node is List) return '[${node.map(_structure).join(',')}]';
    return node is String ? '"$node"' : '$node';
  }

  bool _similarShape(JsonMap a, JsonMap b) {
    final propsA = (a['properties'] as JsonMap?) ?? const {};
    final propsB = (b['properties'] as JsonMap?) ?? const {};
    if (propsA.keys.toSet().difference(propsB.keys.toSet()).isNotEmpty ||
        propsB.keys.toSet().difference(propsA.keys.toSet()).isNotEmpty) {
      return false;
    }
    for (final key in propsA.keys) {
      final ta = spec.deref(propsA[key] as JsonMap);
      final tb = spec.deref(propsB[key] as JsonMap);
      if (_typeName(ta) != _typeName(tb)) return false;
    }
    return true;
  }

  IrType _oneOfType(JsonMap node,
      {required String owner, required String prop}) {
    final alternatives = (node['oneOf'] as List).cast<JsonMap>();
    final discriminator = node['discriminator'];
    if (discriminator is JsonMap) {
      final key = _structureKey(node);
      final known = _unionByStructure[key] ?? _findNamedUnion(key);
      if (known != null) return IrUnionRef(known);
      final override = unionNames.byStructure[key];
      if (override == null) {
        throw StateError(
          'inline discriminated union at $owner.$prop has no name; add it to tool/spec/union_names.yaml under key "$key"',
        );
      }
      _unionFrom(node, _className(override));
      return IrUnionRef(_className(override));
    }
    final allPrimitive = alternatives
        .every((alt) => _primitiveTypeNames.contains(_typeName(alt)));
    if (allPrimitive) return const IrJson();
    throw StateError(
        'undiscriminated oneOf of non-primitives at $owner.$prop is not supported');
  }

  String _structureKey(JsonMap node) {
    final discriminator = node['discriminator'] as JsonMap;
    final mapping = discriminator['mapping'] as JsonMap?;
    final List<String> variants;
    if (mapping != null) {
      variants = mapping.values
          .map((ref) =>
              (ref as String).replaceFirst('#/components/schemas/', ''))
          .toList();
    } else {
      variants = (node['oneOf'] as List).cast<JsonMap>().map((alt) {
        final ref = spec.refName(alt);
        if (ref == null) {
          throw StateError(
              'discriminated union variants must be \$refs when no mapping is given');
        }
        return ref;
      }).toList();
    }
    variants.sort();
    return '${discriminator['propertyName']}|${variants.join(',')}';
  }

  String? _findNamedUnion(String key) {
    for (final entry in spec.schemas.entries) {
      final node = entry.value as JsonMap;
      if (node.containsKey('oneOf') &&
          node.containsKey('discriminator') &&
          _structureKey(node) == key) {
        _classifyNamed(entry.key);
        return _className(entry.key);
      }
    }
    return null;
  }

  void _unionFrom(JsonMap node, String unionName) {
    final discriminator = node['discriminator'] as JsonMap;
    final property = discriminator['propertyName'] as String;
    final mapping = discriminator['mapping'] as JsonMap?;
    final variants = <UnionVariantIr>[];
    final refs = (node['oneOf'] as List)
        .cast<JsonMap>()
        .map((alt) => spec.refName(alt)!)
        .toList();
    if (mapping != null) {
      for (final entry in mapping.entries) {
        final ref =
            (entry.value as String).replaceFirst('#/components/schemas/', '');
        variants.add(
            UnionVariantIr(wireValue: entry.key, className: _className(ref)));
      }
    } else {
      for (final ref in refs) {
        final variant = spec.schema(ref);
        final tag = ((variant['properties'] as JsonMap)[property]
            as JsonMap)['enum'] as List;
        variants.add(UnionVariantIr(
            wireValue: tag.single as String, className: _className(ref)));
      }
    }
    variants.sort((a, b) => a.wireValue.compareTo(b.wireValue));
    _unionByStructure[_structureKey(node)] = unionName;
    unions[unionName] = UnionIr(
      unionName: unionName,
      discriminator: property,
      variants: variants,
      docs: _docOf(node),
    );
    for (final ref in refs) {
      _classifyNamed(ref);
      final variantName = _className(ref);
      final variantClass = classes[variantName];
      final variantUnion = unions[variantName];
      if (variantClass != null) {
        if (variantClass.superType != null &&
            variantClass.superType != unionName) {
          throw StateError(
              '$ref belongs to both ${variantClass.superType} and $unionName');
        }
        variantClass.superType = unionName;
      } else if (variantUnion != null) {
        if (variantUnion.superType != null &&
            variantUnion.superType != unionName) {
          throw StateError(
              '$ref belongs to both ${variantUnion.superType} and $unionName');
        }
        variantUnion.superType = unionName;
      } else {
        throw StateError(
            'union variant $ref is neither an object schema nor a union');
      }
    }
  }

  static const Set<String> _genericEnumNames = {
    'Name',
    'Type',
    'Kind',
    'Mode',
    'State',
    'Status',
    'Ext',
    'Tone',
    'Policy',
    'Resolution',
    'Workflow',
    'Value',
    'Source',
    'Format',
    'Level',
    'Style',
    'Unit',
    'Strategy',
    'Priority',
    'Detail',
    'Action',
    'Via',
    'Object',
  };

  final Map<String, String> _reusableEnumByTuple = {};

  String _inlineEnum(JsonMap node, List<String> values,
      {required String owner, required String prop}) {
    final tuple = _tupleKey(values);
    final key = '$prop|$tuple';
    final existing = _enumByKey[key];
    if (existing != null) return existing;
    final title = node['title'];
    final reusable = _reusableEnumByTuple[tuple] ?? _namedEnumWithTuple(tuple);
    if (reusable != null && title is! String) {
      _enumByKey[key] = reusable;
      return reusable;
    }
    String name;
    if (title is String && title.isNotEmpty) {
      name = _className(title);
    } else if ((_tuplesByProp[prop]?.length ?? 0) <= 1 &&
        !_genericEnumNames.contains(_className(prop)) &&
        _className(prop).length > 4 &&
        !_nameTaken(_className(prop))) {
      name = _className(prop);
    } else {
      name = '${_shortestOwner(key, owner)}${pascalCase(prop)}';
    }
    if (_nameTaken(name)) {
      name = '$owner${pascalCase(prop)}';
      if (_nameTaken(name)) {
        throw StateError('enum name collision for $name ($key)');
      }
    }
    _registerEnum(name, node, values, key: key);
    if (title is String && title.isNotEmpty) _reusableEnumByTuple[tuple] = name;
    return name;
  }

  String _shortestOwner(String key, String fallback) {
    final owners = _enumOwnersByKey[key];
    if (owners == null || owners.isEmpty) return fallback;
    final sorted = owners.toList()
      ..sort((a, b) =>
          a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b));
    return sorted.first;
  }

  String? _namedEnumWithTuple(String tuple) {
    for (final entry in spec.schemas.entries) {
      final values = _stringEnumValues(entry.value as JsonMap);
      if (values != null && values.length > 1 && _tupleKey(values) == tuple) {
        _classifyNamed(entry.key);
        return _className(entry.key);
      }
    }
    return null;
  }

  bool _nameTaken(String name) =>
      classes.containsKey(name) ||
      enums.containsKey(name) ||
      unions.containsKey(name) ||
      spec.schemas.keys.any((schema) => _className(schema) == name);

  void _registerEnum(String name, JsonMap node, List<String> values,
      {required String key}) {
    final deprecatedValues =
        (node['x-mux-doc-decorators-deprecated-enum-values'] as List?)
                ?.cast<String>()
                .toSet() ??
            const {};
    final dartNames = <String>{};
    final entries = <EnumValueIr>[];
    for (final value in values) {
      var dartName = enumValueName(value);
      while (dartNames.contains(dartName)) {
        dartName = '${dartName}_';
      }
      dartNames.add(dartName);
      entries.add(EnumValueIr(
          wire: value,
          dartName: dartName,
          deprecated: deprecatedValues.contains(value)));
    }
    enums[name] = EnumIr(enumName: name, values: entries, docs: _docOf(node));
    _enumByKey[key] = name;
  }

  ClassIr _classFrom(JsonMap node, String rawName,
      {required ClassKind kind, String? origin}) {
    final className = _className(rawName);
    final existing = classes[className];
    if (existing != null) {
      final previous = _classSources[className];
      if (previous != null && _sameShape(previous, node)) return existing;
      throw StateError(
          'class name collision: $className is produced by two different schemas (${existing.origin ?? 'inline'} and ${origin ?? 'inline'})');
    }
    final fields = <FieldIr>[];
    final ir = ClassIr(
        className: className,
        kind: kind,
        fields: fields,
        docs: _docOf(node),
        origin: origin);
    classes[className] = ir;
    _classSources[className] = node;
    final properties = (node['properties'] as JsonMap?) ?? const {};
    final required =
        ((node['required'] as List?)?.cast<String>() ?? const []).toSet();
    final noRequired = node['x-mux-no-required-properties'] == true;
    final usedNames = <String>{};
    for (final entry in properties.entries) {
      final wire = entry.key;
      final property = entry.value as JsonMap;
      final type = _typeOf(property, owner: className, prop: wire);
      var dartName = fieldName(wire);
      while (usedNames.contains(dartName)) {
        dartName = '${dartName}_';
      }
      usedNames.add(dartName);
      final isId = kind == ClassKind.model &&
          wire == 'id' &&
          required.contains('id') &&
          type is IrString;
      fields.add(FieldIr(
        wireName: wire,
        dartName: dartName,
        type: type,
        required: isId ||
            (kind == ClassKind.params &&
                !noRequired &&
                required.contains(wire)),
        docs: _docOf(property),
        deprecated: property['deprecated'] == true,
        deprecationMessage:
            property['x-stainless-deprecation-message'] as String?,
        dateKind: _dateKind(property),
        isId: isId,
        requiredInSpec: !noRequired && required.contains(wire),
      ));
    }
    return ir;
  }

  bool _sameShape(JsonMap a, JsonMap b) =>
      identical(a, b) || a.toString() == b.toString();

  DateKind _dateKind(JsonMap property) {
    if (_typeName(property) != 'string') return DateKind.none;
    final format = property['format'];
    if (format == 'int64') return DateKind.unixSecondsString;
    if (format == 'date-time') return DateKind.isoString;
    return DateKind.none;
  }

  void _resolveOperations() {
    final keys = <String>[];
    for (final pathEntry in spec.paths.entries) {
      for (final method in (pathEntry.value as JsonMap).keys) {
        if (!const {'get', 'post', 'put', 'patch', 'delete'}.contains(method)) {
          continue;
        }
        keys.add('${method.toUpperCase()} ${pathEntry.key}');
      }
    }
    keys.sort();
    for (final key in keys) {
      if (operationMap.excluded.contains(key)) continue;
      final mapping = operationMap.operations[key];
      if (mapping == null) {
        throw StateError(
            'operation $key is neither mapped nor excluded in tool/spec/resources.yaml');
      }
      _resolveOperation(key, mapping);
    }
    for (final mapped in operationMap.operations.keys) {
      if (!keys.contains(mapped)) {
        throw StateError(
            'resources.yaml maps $mapped, which the spec does not define');
      }
    }
  }

  void _resolveOperation(String key, OperationMapping mapping) {
    final space = key.indexOf(' ');
    final verb = key.substring(0, space);
    final path = key.substring(space + 1);
    final operation =
        (spec.paths[path]! as JsonMap)[verb.toLowerCase()]! as JsonMap;
    final pathItem = spec.paths[path]! as JsonMap;
    final namespace = _namespaceFor(mapping.namespace);
    final resourceClass = namespace.className;
    final methodPascal = pascalCase(mapping.method);

    final pathParams = <ParamIr>[];
    final queryParams = <ParamIr>[];
    final rawParams = [
      ...((pathItem['parameters'] as List?) ?? const []).cast<JsonMap>(),
      ...((operation['parameters'] as List?) ?? const []).cast<JsonMap>(),
    ].map(spec.parameter);
    for (final param in rawParams) {
      final name = param['name'] as String;
      final schema =
          spec.deref((param['schema'] as JsonMap?) ?? const {'type': 'string'});
      final type = _paramType(schema, '$resourceClass$methodPascal', name);
      final ir = ParamIr(
        wireName: name,
        dartName: param['in'] == 'path' ? pathParamName(name) : fieldName(name),
        type: type,
        required: param['required'] == true || param['in'] == 'path',
        docs: _docOf(param),
        enumValues: _paramEnumValues(schema),
      );
      (param['in'] == 'path' ? pathParams : queryParams).add(ir);
    }
    final orderedPathParams = <ParamIr>[];
    for (final match in RegExp(r'\{([^}]+)\}').allMatches(path)) {
      final placeholder = match.group(1)!;
      orderedPathParams.add(pathParams.firstWhere(
        (param) => param.wireName == placeholder,
        orElse: () => throw StateError(
            '$key: path parameter $placeholder is not declared'),
      ));
    }

    String? bodyClass;
    final requestBody = operation['requestBody'] as JsonMap?;
    if (requestBody != null) {
      final content = requestBody['content'] as JsonMap;
      final jsonBody = content['application/json'] as JsonMap?;
      if (jsonBody == null) {
        throw StateError(
            '$key: only application/json request bodies are supported');
      }
      var schema = spec.deref(jsonBody['schema'] as JsonMap);
      if (schema.containsKey('allOf')) schema = _flattenAllOf(schema);
      final paramsName =
          '${singular(pascalCase(mapping.namespace.last))}${methodPascal}Params';
      bodyClass =
          _classFrom(schema, paramsName, kind: ClassKind.params, origin: key)
              .className;
      _recordExample(bodyClass, jsonBody['example']);
    }

    final responses = operation['responses'] as JsonMap;
    final successCode = ['200', '201', '202', '204'].firstWhere(
        responses.containsKey,
        orElse: () => throw StateError('$key has no 2xx response'));
    final success = responses[successCode] as JsonMap;
    final content = success['content'] as JsonMap?;
    ResponseIr response;
    String accept;
    if (content == null || content.isEmpty) {
      response = const VoidResponse();
      accept = '*/*';
    } else if (content.containsKey('application/json')) {
      final jsonResponse = content['application/json'] as JsonMap;
      final rawSchema = jsonResponse['schema'] as JsonMap;
      final schema = spec.deref(rawSchema);
      accept = 'application/json';
      if (_typeName(schema) == 'string') {
        response = const TextResponse();
      } else {
        response = _jsonResponse(schema, spec.refName(rawSchema), mapping,
            '$resourceClass$methodPascal', key);
        _recordResponseExample(response, jsonResponse['example']);
      }
    } else if (content.keys.every((type) => type.startsWith('text/'))) {
      response = const TextResponse();
      accept = content.keys.single;
    } else {
      response = const BytesResponse();
      accept = content.length == 1 ? content.keys.single : 'application/binary';
    }

    final servers = operation['servers'] as List?;
    final serverUrl = servers == null || servers.isEmpty
        ? 'https://api.mux.com'
        : (servers.first as JsonMap)['url'] as String;
    final host = switch (serverUrl) {
      'https://api.mux.com' => 'api',
      'https://image.mux.com' => 'image',
      'https://stream.mux.com' => 'stream',
      'https://stats.mux.com' => 'stats',
      _ => throw StateError('$key: unknown server $serverUrl'),
    };

    namespace.operations.add(OperationIr(
      namespacePath: mapping.namespace,
      methodName: mapping.method,
      httpMethod: verb,
      pathTemplate: path,
      pathParams: orderedPathParams,
      queryParams: queryParams,
      bodyClass: bodyClass,
      response: response,
      host: host,
      accept: accept,
      docs: [operation['summary'], operation['description']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join('\n\n'),
      deprecated: operation['deprecated'] == true,
      deprecationMessage:
          operation['x-stainless-deprecation-message'] as String?,
    ));
  }

  List<String>? _paramEnumValues(JsonMap schema) {
    if (schema.containsKey('allOf')) {
      final parts = (schema['allOf'] as List)
          .cast<JsonMap>()
          .where(_isSubstantive)
          .toList();
      return parts.length == 1
          ? _paramEnumValues(spec.deref(parts.single))
          : null;
    }
    final values = schema['enum'];
    if (values is! List) return null;
    final literals = values
        .where((value) => value is String || value is num)
        .map((value) => value.toString())
        .toList();
    return literals.isEmpty ? null : literals;
  }

  IrType _paramType(JsonMap schema, String owner, String name) {
    if (schema.containsKey('allOf')) {
      final parts = (schema['allOf'] as List)
          .cast<JsonMap>()
          .where(_isSubstantive)
          .toList();
      if (parts.length != 1) {
        throw StateError(
            '$owner.$name: allOf parameter schemas must have one substantive part');
      }
      return _paramType(spec.deref(parts.single), owner, name);
    }
    final type =
        _typeName(schema) ?? (schema.containsKey('enum') ? 'string' : null);
    switch (type) {
      case 'string':
        return const IrString();
      case 'integer':
        return const IrInt();
      case 'number':
        return const IrDouble();
      case 'boolean':
        return const IrBool();
      case 'array':
        final items = spec
            .deref((schema['items'] as JsonMap?) ?? const {'type': 'string'});
        return IrList(_paramType(items, owner, name));
      default:
        throw StateError('$owner.$name: unsupported parameter type $type');
    }
  }

  ResponseIr _jsonResponse(JsonMap schema, String? schemaName,
      OperationMapping mapping, String inlineName, String key) {
    final properties = (schema['properties'] as JsonMap?) ?? const {};
    final required = ((schema['required'] as List?)?.cast<String>() ?? const [])
        .toList()
      ..sort();
    final data = properties['data'] as JsonMap?;
    if (mapping.page != null) {
      if (data == null || _typeName(data) != 'array') {
        throw StateError('$key is mapped as a page but has no data array');
      }
      final items = data['items'] as JsonMap;
      final itemType = _typeOf(items, owner: inlineName, prop: 'item');
      final kind = switch (mapping.page) {
        'base' => PageKind.base,
        'cursor' => PageKind.cursor,
        'withTimeframe' => PageKind.withTimeframe,
        'withTotal' => PageKind.withTotal,
        _ => throw StateError('$key: unknown page kind ${mapping.page}'),
      };
      return PageResponse(kind, itemType);
    }
    if (data != null && required.length == 1 && required.single == 'data') {
      return UnwrapResponse(_typeOf(data, owner: inlineName, prop: 'data'));
    }
    if (schemaName != null) {
      _classifyNamed(schemaName);
      return EnvelopeResponse(_className(schemaName));
    }
    return EnvelopeResponse(_classFrom(schema, '${inlineName}Response',
            kind: ClassKind.model, origin: key)
        .className);
  }

  void _recordResponseExample(ResponseIr response, Object? example) {
    if (example is! JsonMap) return;
    switch (response) {
      case UnwrapResponse(type: IrRef(:final className)):
        _recordExample(className, example['data']);
      case UnwrapResponse(type: IrList(element: IrRef(:final className))):
        for (final item in (example['data'] as List?) ?? const []) {
          _recordExample(className, item);
        }
      case PageResponse(itemType: IrRef(:final className)):
        for (final item in (example['data'] as List?) ?? const []) {
          _recordExample(className, item);
        }
      case EnvelopeResponse(:final className):
        _recordExample(className, example);
      default:
        break;
    }
  }

  NamespaceIr _namespaceFor(List<String> path) {
    NamespaceIr? current;
    Map<String, NamespaceIr> level = namespaces;
    for (var i = 0; i < path.length; i++) {
      final segment = path[i];
      final prefix = path.sublist(0, i + 1);
      final className =
          i == 0 ? 'Mux${pascalCase(segment)}' : prefix.map(pascalCase).join();
      current = level.putIfAbsent(
          segment, () => NamespaceIr(path: prefix, className: className));
      level = current.children;
    }
    return current!;
  }

  void _resolveWebhooks() {
    final keys = spec.webhooks.keys.toList()..sort();
    for (final key in keys) {
      final post = (spec.webhooks[key] as JsonMap)['post'] as JsonMap;
      final requestBody = post['requestBody'] as JsonMap;
      final schema =
          (requestBody['content'] as JsonMap)['application/json'] as JsonMap;
      final root = schema['schema'] as JsonMap;
      final className = '${pascalCase(key)}Event';
      final segments = key.split('.');
      final familyOwner =
          '${pascalCase(segments.sublist(0, segments.length - 1).join('.'))}Event';
      IrType? dataType;
      final parts = (root['allOf'] as List).cast<JsonMap>();
      for (final part in parts) {
        if (spec.refName(part) == 'BaseWebhookEvent') continue;
        final properties = (part['properties'] as JsonMap?) ?? const {};
        final data = properties['data'] as JsonMap?;
        if (data != null) {
          dataType = _typeOf(data, owner: familyOwner, prop: 'data');
        }
      }
      webhooks.add(WebhookIr(
        eventType: key,
        className: className,
        dataType: dataType,
        docs: (requestBody['description'] as String?) ?? '',
      ));
    }
  }
}
