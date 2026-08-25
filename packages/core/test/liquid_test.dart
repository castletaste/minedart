import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('all four-bit metadata values preserve level and falling state', () {
    for (var metadata = 0; metadata < 16; metadata++) {
      final raw = Blocks.pack(Blocks.water, metadata);
      expect(LiquidState.level(raw), metadata & 7);
      expect(LiquidState.isFalling(raw), (metadata & 8) != 0);
      expect(
        LiquidState.metadata(
          LiquidState.level(raw),
          falling: LiquidState.isFalling(raw),
        ),
        metadata,
      );
    }
  });

  test('surface height uses Alpha levels and falling is source-height', () {
    expect(LiquidState.surfaceHeight(Blocks.pack(Blocks.water)), 8 / 9);
    expect(LiquidState.surfaceHeight(Blocks.pack(Blocks.water, 7)), 1 / 9);
    expect(
      LiquidState.surfaceHeight(
        LiquidState.pack(Blocks.lava, 5, falling: true),
      ),
      8 / 9,
    );
  });

  test('liquid identity is independent from metadata', () {
    expect(LiquidState.isLiquid(Blocks.pack(Blocks.water, 15)), isTrue);
    expect(LiquidState.isLiquid(Blocks.pack(Blocks.lava, 8)), isTrue);
    expect(LiquidState.isLiquid(Blocks.pack(Blocks.obsidian, 15)), isFalse);
  });
}
