/// Shared metadata contract for Minedart's single-ID Alpha liquid profile.
library;

import 'block.dart';

abstract final class LiquidState {
  static const int levelMask = 0x7;
  static const int fallingBit = 0x8;
  static const int maxLevel = 7;

  /// Horizontal flow level in the inclusive range 0 through 7.
  static int level(int raw) => Blocks.meta(raw) & levelMask;

  /// Whether metadata carries Alpha's falling-flow flag.
  static bool isFalling(int raw) => (Blocks.meta(raw) & fallingBit) != 0;

  /// Encodes a level and falling flag into the existing four metadata bits.
  static int metadata(int level, {bool falling = false}) {
    assert(level >= 0 && level <= maxLevel);
    return (level & levelMask) | (falling ? fallingBit : 0);
  }

  static int pack(int blockId, int level, {bool falling = false}) =>
      Blocks.pack(blockId, metadata(level, falling: falling));

  static bool isLiquidId(int blockId) =>
      blockId == Blocks.water || blockId == Blocks.lava;

  static bool isLiquid(int raw) => isLiquidId(Blocks.id(raw));

  /// Alpha's local surface height before corner averaging.
  ///
  /// Falling metadata is an effective source level. A same-fluid cell above
  /// is handled by the caller and raises the visible column to a full block.
  static double surfaceHeight(int raw) {
    final effectiveLevel = isFalling(raw) ? 0 : level(raw);
    return (8 - effectiveLevel) / 9;
  }
}
