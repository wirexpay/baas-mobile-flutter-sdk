/// `e2e.local.json` holds a test user's private key and `pubspec_overrides.yaml` a local plugin path:
/// neither may reach a commit, so the repository's `.gitignore` must name both.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the root .gitignore names e2e.local.json and pubspec_overrides.yaml', () {
    final List<String> lines = File('../.gitignore').readAsLinesSync().map((String line) => line.trim()).toList();
    expect(lines, contains('e2e.local.json'));
    expect(lines, contains('pubspec_overrides.yaml'));
  });
}
