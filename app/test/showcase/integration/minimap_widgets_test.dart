import 'dart:typed_data';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/integration/minimap_widgets.dart';
import 'package:minedart/showcase/render/minimap_snapshot.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  ValueNotifier<MinimapViewState> state() => ValueNotifier<MinimapViewState>(
    MinimapViewState(
      snapshot: MinimapSnapshot.fromHeightmap(
        width: 3,
        depth: 2,
        heights: Uint8List.fromList(<int>[3, 3, 3, 3, 3, 3]),
        surfaceBlockIds: Uint16List.fromList(<int>[
          Blocks.grass,
          Blocks.grass,
          Blocks.grass,
          Blocks.grass,
          Blocks.grass,
          Blocks.grass,
        ]),
      ),
      playerX: 0,
      playerZ: 0,
      heading: 0,
    ),
  );

  testWidgets('moves, labels, and paints the selected cell from the keyboard', (
    tester,
  ) async {
    final paints = <(int, int, int, int)>[];
    final minimapState = state();
    addTearDown(minimapState.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MinimapEditorDialog(
            state: minimapState,
            blockId: Blocks.sand,
            onPaintSurface: (x, z, blockId, radius) =>
                paints.add((x, z, blockId, radius)),
          ),
        ),
      ),
    );

    expect(find.text('Selected cell: 1, 1'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(find.text('Selected cell: 2, 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(paints, <(int, int, int, int)>[(1, 1, Blocks.sand, 0)]);
  });

  testWidgets('keeps mouse painting while updating the selected cell', (
    tester,
  ) async {
    final paints = <(int, int, int, int)>[];
    final minimapState = state();
    addTearDown(minimapState.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MinimapEditorDialog(
            state: minimapState,
            blockId: Blocks.sand,
            onPaintSurface: (x, z, blockId, radius) =>
                paints.add((x, z, blockId, radius)),
          ),
        ),
      ),
    );

    final map = find.byKey(const ValueKey<String>('minimap-editor-map'));
    final bounds = tester.getRect(map);
    await tester.tapAt(bounds.bottomRight - const Offset(2, 2));
    await tester.pump();

    expect(find.text('Selected cell: 3, 2'), findsOneWidget);
    expect(paints, <(int, int, int, int)>[(2, 1, Blocks.sand, 0)]);
  });

  testWidgets('exposes a focusable semantic map action', (tester) async {
    final semantics = tester.ensureSemantics();
    final minimapState = state();
    addTearDown(minimapState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MinimapEditorDialog(
            state: minimapState,
            blockId: Blocks.sand,
            onPaintSurface: (_, _, _, _) {},
          ),
        ),
      ),
    );

    final node = tester.getSemantics(
      find.byKey(const ValueKey<String>('minimap-editor-map')),
    );
    final data = node.getSemanticsData();
    expect(data.label, contains('Terrain map'));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });
}
