import 'dart:typed_data';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/integration/minimap_widgets.dart';
import 'package:minedart/showcase/render/minimap_snapshot.dart';
import 'package:minedart_core/minedart_core.dart';

void main() {
  testWidgets('minimap is a passive image and absorbs pointer input', (
    tester,
  ) async {
    final minimapState = ValueNotifier<MinimapViewState>(
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
        playerX: 1,
        playerZ: 1,
        heading: 0,
      ),
    );
    addTearDown(minimapState.dispose);
    var gameTaps = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => gameTaps++,
                ),
              ),
              MinimapOverlay(state: minimapState),
            ],
          ),
        ),
      ),
    );

    final overlay = find.byKey(const ValueKey<String>('minimap-overlay'));
    expect(
      find.byKey(const ValueKey<String>('minimap-terrain-boundary')),
      findsOneWidget,
    );
    final node = tester.getSemantics(overlay).getSemanticsData();
    expect(node.label, 'World minimap');
    expect(node.hasAction(SemanticsAction.tap), isFalse);

    await tester.tapAt(tester.getCenter(overlay));
    await tester.pump();
    expect(gameTaps, 0);
    expect(find.textContaining('Minimap editor'), findsNothing);
    semantics.dispose();
  });
}
