import 'dart:convert';
import 'dart:io';

Map<String, Object?> loadFixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> casesOf(Map<String, Object?> fixture) =>
    (fixture['cases']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> mapOf(Object? value) => value as Map<String, Object?>;

List<String> stringListOf(Object? value) =>
    (value as List<Object?>).cast<String>();
