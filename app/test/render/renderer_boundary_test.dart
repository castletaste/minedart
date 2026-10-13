import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rendering goes through `lib/render/voxel_renderer.dart`. Only the flame_3d
/// adapter and the Flame host binding may import the engine directly.
const _flame3dImportAllowlist = <String>{'lib/game/minedart_game.dart'};
const _flame3dAdapterDirectory = 'lib/render/flame3d/';

void main() {
  test('flame_3d is imported only by the adapter and the Flame host', () {
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.startsWith(_flame3dAdapterDirectory) ||
          _flame3dImportAllowlist.contains(path)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if ((line.startsWith('import ') || line.startsWith('export ')) &&
            line.contains('package:flame_3d/')) {
          violations.add('$path:${i + 1}: $line');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the renderer port itself is engine-free', () {
    final imports = File(
      'lib/render/voxel_renderer.dart',
    ).readAsLinesSync().where((line) => line.startsWith('import '));
    for (final line in imports) {
      expect(line, isNot(contains('flame')), reason: line);
    }
  });
}
