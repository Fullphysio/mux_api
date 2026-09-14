final class DartWriter {
  final StringBuffer _buffer = StringBuffer();
  int _indent = 0;

  void line([String text = '']) {
    if (text.isEmpty) {
      _buffer.writeln();
    } else {
      _buffer.writeln('${'  ' * _indent}$text');
    }
  }

  void block(String header, void Function() body, {String close = '}'}) {
    line(header);
    _indent++;
    body();
    _indent--;
    line(close);
  }

  void doc(String? text, {required String fallback}) {
    final content = sanitizeDoc(text ?? '');
    final lines = content.isEmpty ? [fallback] : content.split('\n');
    for (final docLine in lines) {
      line(docLine.isEmpty ? '///' : '/// $docLine');
    }
  }

  @override
  String toString() => _buffer.toString();
}

String sanitizeDoc(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll('*/', '* /')
      .split('\n')
      .map((line) => line.trimRight())
      .toList();
  while (lines.isNotEmpty && lines.first.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  final collapsed = <String>[];
  for (final line in lines) {
    if (line.isEmpty && collapsed.isNotEmpty && collapsed.last.isEmpty) {
      continue;
    }
    collapsed.add(line);
  }
  return collapsed.join('\n');
}

String dartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}
