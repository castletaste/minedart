import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _allowlistStart = '<!-- BEGIN INTENTIONAL CHANGE ALLOWLIST -->';
const _allowlistEnd = '<!-- END INTENTIONAL CHANGE ALLOWLIST -->';
const _upstreamPackageSha256 =
    '45310da41e63a690d79514b24f890b28251c3066aa0986db29ef48283541af0a';

const _generatedFileNames = <String>{
  '.flutter-plugins-dependencies',
  '.packages',
  'pubspec.lock',
};

const _generatedDirectoryNames = <String>{'.dart_tool', 'build', 'coverage'};

void main() {
  test(
    'vendored tree matches upstream outside the explicit allow-list',
    () async {
      final root = _packageRoot();
      final upstream = _readManifest(
        File('${root.path}/UPSTREAM_MANIFEST.sha256'),
      );
      final upstreamDocument = File('${root.path}/UPSTREAM.md');
      final allowlist = _readAllowlist(upstreamDocument);
      final actualPaths = _vendoredFiles(root);
      final expectedPaths = {...upstream.keys, ...allowlist};
      final failures = <String>[];

      if (upstream.length != 179) {
        failures.add(
          'manifest file count: expected 179, got ${upstream.length}',
        );
      }
      if (!actualPaths.contains('LICENSE')) {
        failures.add('upstream MIT LICENSE is missing');
      }
      if (!upstreamDocument.readAsStringSync().contains(
        _upstreamPackageSha256,
      )) {
        failures.add('UPSTREAM.md has the wrong pub package SHA-256');
      }

      final missing = expectedPaths.difference(actualPaths).toList()..sort();
      final unexpected = actualPaths.difference(expectedPaths).toList()..sort();
      if (missing.isNotEmpty) {
        failures.add('missing files: ${missing.join(', ')}');
      }
      if (unexpected.isNotEmpty) {
        failures.add('unexpected files: ${unexpected.join(', ')}');
      }

      for (final entry in upstream.entries) {
        if (allowlist.contains(entry.key)) {
          continue;
        }
        final file = File('${root.path}/${entry.key}');
        if (!file.existsSync()) {
          continue;
        }
        final actualHash = sha256.convert(await file.readAsBytes()).toString();
        if (actualHash != entry.value) {
          failures.add(
            '${entry.key}: expected ${entry.value}, got $actualHash',
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    },
  );
}

Directory _packageRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (File('${candidate.path}/UPSTREAM.md').existsSync() &&
        File('${candidate.path}/pubspec.yaml').existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Unable to locate the vendored flame_3d package.');
    }
    candidate = parent;
  }
}

Map<String, String> _readManifest(File file) {
  final entries = <String, String>{};
  final pattern = RegExp(r'^([0-9a-f]{64})  \./(.+)$');
  for (final line in file.readAsLinesSync()) {
    final match = pattern.firstMatch(line);
    if (match == null) {
      throw FormatException('Invalid upstream manifest line: $line');
    }
    final path = match.group(2)!;
    if (entries[path] != null) {
      throw FormatException('Duplicate upstream manifest path: $path');
    }
    entries[path] = match.group(1)!;
  }
  return entries;
}

Set<String> _readAllowlist(File file) {
  final lines = file.readAsLinesSync();
  final start = lines.indexOf(_allowlistStart);
  final end = lines.indexOf(_allowlistEnd);
  if (start == -1 || end <= start) {
    throw FormatException('UPSTREAM.md has no valid allow-list markers.');
  }

  final paths = <String>[];
  final pattern = RegExp(r'^- `([^`]+)`$');
  for (final line in lines.sublist(start + 1, end)) {
    final match = pattern.firstMatch(line);
    if (match == null) {
      throw FormatException('Invalid allow-list line: $line');
    }
    paths.add(match.group(1)!);
  }
  final sorted = [...paths]..sort();
  if (!_listEquals(paths, sorted)) {
    throw FormatException('UPSTREAM.md allow-list must stay sorted.');
  }
  if (paths.toSet().length != paths.length) {
    throw FormatException('UPSTREAM.md allow-list contains duplicates.');
  }
  return paths.toSet();
}

Set<String> _vendoredFiles(Directory root) {
  final rootPath = root.path.endsWith(Platform.pathSeparator)
      ? root.path
      : '${root.path}${Platform.pathSeparator}';
  return root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((file) => file.path.substring(rootPath.length))
      .map((path) => path.replaceAll(Platform.pathSeparator, '/'))
      .where((path) => !_isGenerated(path))
      .toSet();
}

bool _isGenerated(String path) {
  final segments = path.split('/');
  return _generatedFileNames.contains(segments.last) ||
      segments.any(_generatedDirectoryNames.contains);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
