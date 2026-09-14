const Map<String, String> _acronyms = {
  'ID': 'Id',
  'IDS': 'Ids',
  'DRM': 'Drm',
  'MP4': 'Mp4',
  'HLS': 'Hls',
  'URL': 'Url',
  'URLS': 'Urls',
  'VTT': 'Vtt',
  'CORS': 'Cors',
  'API': 'Api',
  'JWT': 'Jwt',
  'RTMP': 'Rtmp',
  'SRT': 'Srt',
  'UTC': 'Utc',
  'CDN': 'Cdn',
  'AI': 'Ai',
  'GIF': 'Gif',
  'DVR': 'Dvr',
  'FPS': 'Fps',
  'HTTP': 'Http',
  'JSON': 'Json',
  'UUID': 'Uuid',
  'HD': 'Hd',
  'SD': 'Sd',
  'UHD': 'Uhd',
  'FHD': 'Fhd',
  'CDNS': 'Cdns',
  'ASN': 'Asn',
  'ISO': 'Iso',
  'MS': 'Ms',
  'TTL': 'Ttl',
  'LLM': 'Llm',
};

const Set<String> _reservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

const Set<String> _memberNamesToAvoid = {
  'hashCode',
  'runtimeType',
  'toString',
  'noSuchMethod',
  'raw',
  'toJson',
  'fromJson',
  'values',
  'value',
  'isKnown',
  'fromWire',
};

final RegExp _camelTokens =
    RegExp(r'[A-Z]+[0-9]*(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+');
final RegExp _separators = RegExp(r'[_\-\s,./]+');

List<String> _tokens(String text) {
  final words = <String>[];
  for (final chunk in text.split(_separators)) {
    if (chunk.isEmpty) continue;
    for (final match in _camelTokens.allMatches(chunk)) {
      words.add(match.group(0)!);
    }
  }
  return words;
}

String _titleCase(String word) {
  final upper = word.toUpperCase();
  final acronym = _acronyms[upper];
  if (acronym != null) return acronym;
  if (word.length > 1 &&
      word == upper &&
      RegExp(r'^[A-Z]+[0-9]*$').hasMatch(word)) {
    return word[0] + word.substring(1).toLowerCase();
  }
  return word[0].toUpperCase() + word.substring(1);
}

String pascalCase(String text) {
  final words = _tokens(text).map(_titleCase).join();
  if (words.isEmpty) throw StateError('cannot derive a Dart name from "$text"');
  return words;
}

String camelCase(String text) {
  final pascal = pascalCase(text.replaceFirst(RegExp(r'^_+'), ''));
  final camel = pascal[0].toLowerCase() + pascal.substring(1);
  return camel;
}

String fieldName(String wireName) {
  var name = camelCase(wireName);
  if (RegExp(r'^[0-9]').hasMatch(name)) name = 'v$name';
  if (_reservedWords.contains(name) || _memberNamesToAvoid.contains(name)) {
    name = '${name}Value';
  }
  return name;
}

String enumValueName(String wireValue) {
  var name = wireValue.trim().isEmpty
      ? 'empty'
      : camelCase(wireValue.replaceAll(RegExp(r'[^A-Za-z0-9_\-\s,./]'), ' '));
  if (name.isEmpty) name = 'empty';
  if (RegExp(r'^[0-9]').hasMatch(name)) name = 'v$name';
  if (_reservedWords.contains(name) || _memberNamesToAvoid.contains(name)) {
    name = '${name}Value';
  }
  return name;
}

String singular(String word) {
  if (word.endsWith('ies') && word.length > 3) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.endsWith('ses') ||
      word.endsWith('xes') ||
      word.endsWith('ches') ||
      word.endsWith('shes')) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s') && !word.endsWith('ss') && word.length > 1) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

String snakeCase(String pascal) {
  final buffer = StringBuffer();
  for (final token in _tokens(pascal)) {
    if (buffer.isNotEmpty) buffer.write('_');
    buffer.write(token.toLowerCase());
  }
  return buffer.toString();
}

String pathParamName(String placeholder) =>
    camelCase(placeholder.toLowerCase());
