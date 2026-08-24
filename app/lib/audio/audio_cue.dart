import 'package:minedart_core/minedart_core.dart';

/// The kind of block interaction that can emit a material sound.
enum BlockAudioAction { breakBlock, placeBlock, step }

/// Classic-inspired procedural cues. Material interactions deliberately share
/// a bank of short samples, as Classic used its step sounds for breaking too.
enum AudioCue {
  stoneBreak(_stoneVariants, 0.64, 0.94, 1.02),
  stonePlace(_stoneVariants, 0.48, 0.96, 1.03),
  stoneHighBreak(_stoneVariants, 0.68, 1.34, 1.43),
  stoneHighPlace(_stoneVariants, 0.52, 1.37, 1.46),
  grassBreak(_grassVariants, 0.68, 0.99, 1.03),
  grassPlace(_grassVariants, 0.52, 1.00, 1.03),
  woodBreak(_woodVariants, 0.70, 0.99, 1.03),
  woodPlace(_woodVariants, 0.54, 1.00, 1.03),
  gravelBreak(_gravelVariants, 0.70, 0.97, 1.04),
  gravelPlace(_gravelVariants, 0.54, 1.00, 1.06),
  // Reserved because deterministic variation historically used enum indices;
  // removing this slot would change every later cue, including dirt.
  legacyGrassStep(_grassVariants, 0.30, 0.98, 1.04),
  water(['audio/water.wav'], 0.42, 0.96, 1.04),
  tntFuse(['audio/tnt_fuse.wav'], 0.68, 0.98, 1.02),
  explosion(['audio/explosion.wav'], 0.88, 0.92, 1.01),
  uiClick(['audio/ui_click.wav'], 0.46, 0.99, 1.01),
  dirtBreak(_dirtVariants, 0.58, 0.99, 1.02),
  dirtPlace(_dirtVariants, 0.44, 1.00, 1.03),
  leavesBreak(_leavesVariants, 0.54, 0.99, 1.02),
  leavesPlace(_leavesVariants, 0.40, 1.00, 1.03),
  stoneStep(_stoneVariants, 0.22, 0.90, 0.98),
  stoneHighStep(_stoneVariants, 0.18, 1.16, 1.24),
  grassStep(_grassVariants, 0.20, 0.94, 1.00),
  dirtStep(_dirtVariants, 0.20, 0.94, 1.00),
  leavesStep(_leavesVariants, 0.17, 0.94, 1.00),
  woodStep(_woodVariants, 0.21, 0.94, 1.00),
  gravelStep(_gravelVariants, 0.21, 0.92, 1.00),
  metalBreak(_metalVariants, 0.60, 0.94, 1.02),
  metalPlace(_metalVariants, 0.46, 0.96, 1.03),
  metalStep(_metalVariants, 0.20, 0.92, 1.00);

  const AudioCue(
    this.assetPaths,
    this.baseVolume,
    this.minPitch,
    this.maxPitch,
  );

  /// Paths relative to Flutter's `assets/` directory.
  final List<String> assetPaths;

  /// Cue-specific volume before the user SFX volume is applied.
  final double baseVolume;
  final double minPitch;
  final double maxPitch;

  String assetPathFor(int variantIndex) =>
      assetPaths[variantIndex % assetPaths.length];

  /// Maps stable block IDs to Classic-style shared material banks.
  ///
  /// Break, place, and step cues deliberately vary playback of the same WAV
  /// files instead of owning action-specific recordings.
  static AudioCue forBlock(int blockId, BlockAudioAction action) {
    final material = _materialFor(blockId);
    return switch ((material, action)) {
      (AudioMaterial.stone, BlockAudioAction.breakBlock) => stoneBreak,
      (AudioMaterial.stone, BlockAudioAction.placeBlock) => stonePlace,
      (AudioMaterial.stone, BlockAudioAction.step) => stoneStep,
      (AudioMaterial.stoneHigh, BlockAudioAction.breakBlock) => stoneHighBreak,
      (AudioMaterial.stoneHigh, BlockAudioAction.placeBlock) => stoneHighPlace,
      (AudioMaterial.stoneHigh, BlockAudioAction.step) => stoneHighStep,
      (AudioMaterial.grass, BlockAudioAction.breakBlock) => grassBreak,
      (AudioMaterial.grass, BlockAudioAction.placeBlock) => grassPlace,
      (AudioMaterial.grass, BlockAudioAction.step) => grassStep,
      (AudioMaterial.dirt, BlockAudioAction.breakBlock) => dirtBreak,
      (AudioMaterial.dirt, BlockAudioAction.placeBlock) => dirtPlace,
      (AudioMaterial.dirt, BlockAudioAction.step) => dirtStep,
      (AudioMaterial.leaves, BlockAudioAction.breakBlock) => leavesBreak,
      (AudioMaterial.leaves, BlockAudioAction.placeBlock) => leavesPlace,
      (AudioMaterial.leaves, BlockAudioAction.step) => leavesStep,
      (AudioMaterial.wood, BlockAudioAction.breakBlock) => woodBreak,
      (AudioMaterial.wood, BlockAudioAction.placeBlock) => woodPlace,
      (AudioMaterial.wood, BlockAudioAction.step) => woodStep,
      (AudioMaterial.gravel, BlockAudioAction.breakBlock) => gravelBreak,
      (AudioMaterial.gravel, BlockAudioAction.placeBlock) => gravelPlace,
      (AudioMaterial.gravel, BlockAudioAction.step) => gravelStep,
      (AudioMaterial.metal, BlockAudioAction.breakBlock) => metalBreak,
      (AudioMaterial.metal, BlockAudioAction.placeBlock) => metalPlace,
      (AudioMaterial.metal, BlockAudioAction.step) => metalStep,
      (AudioMaterial.water, _) => water,
    };
  }

  static AudioMaterial _materialFor(int blockId) {
    return switch (blockId) {
      Blocks.grass ||
      Blocks.flowerDandelion ||
      Blocks.flowerRose ||
      Blocks.clothWhite ||
      Blocks.clothRed ||
      Blocks.clothOrange ||
      Blocks.clothYellow ||
      Blocks.clothLime ||
      Blocks.clothBlue => AudioMaterial.grass,
      Blocks.dirt || Blocks.sponge => AudioMaterial.dirt,
      Blocks.leavesOak ||
      Blocks.mushroomBrown ||
      Blocks.mushroomRed ||
      Blocks.sapling => AudioMaterial.leaves,
      Blocks.sand || Blocks.gravel => AudioMaterial.gravel,
      Blocks.logOak || Blocks.planksOak => AudioMaterial.wood,
      Blocks.glass => AudioMaterial.stoneHigh,
      Blocks.goldBlock || Blocks.ironBlock => AudioMaterial.metal,
      Blocks.water || Blocks.lava => AudioMaterial.water,
      _ => AudioMaterial.stone,
    };
  }
}

enum AudioMaterial {
  stone,
  stoneHigh,
  grass,
  dirt,
  leaves,
  wood,
  gravel,
  water,
  metal,
}

const _stoneVariants = <String>[
  'audio/stone_1.wav',
  'audio/stone_2.wav',
  'audio/stone_3.wav',
  'audio/stone_4.wav',
];
const _grassVariants = <String>[
  'audio/grass_1.wav',
  'audio/grass_2.wav',
  'audio/grass_3.wav',
  'audio/grass_4.wav',
];
const _dirtVariants = <String>[
  'audio/dirt_1.wav',
  'audio/dirt_2.wav',
  'audio/dirt_3.wav',
  'audio/dirt_4.wav',
];
const _leavesVariants = <String>[
  'audio/leaves_1.wav',
  'audio/leaves_2.wav',
  'audio/leaves_3.wav',
  'audio/leaves_4.wav',
];
const _woodVariants = <String>[
  'audio/wood_1.wav',
  'audio/wood_2.wav',
  'audio/wood_3.wav',
  'audio/wood_4.wav',
];
const _gravelVariants = <String>[
  'audio/gravel_1.wav',
  'audio/gravel_2.wav',
  'audio/gravel_3.wav',
  'audio/gravel_4.wav',
];
const _metalVariants = <String>[
  'audio/metal_1.wav',
  'audio/metal_2.wav',
  'audio/metal_3.wav',
  'audio/metal_4.wav',
];

/// Deterministic per-playback sample, volume, and pitch selection.
final class AudioVariation {
  const AudioVariation({
    required this.variantIndex,
    required this.volume,
    required this.pitch,
  });

  final int variantIndex;
  final double volume;
  final double pitch;

  @override
  bool operator ==(Object other) {
    return other is AudioVariation &&
        other.variantIndex == variantIndex &&
        other.volume == volume &&
        other.pitch == pitch;
  }

  @override
  int get hashCode => Object.hash(variantIndex, volume, pitch);
}

AudioVariation audioVariation(AudioCue cue, int seed) {
  var state = (seed ^ (cue.index * 0x9E3779B9)) & 0x7FFFFFFF;
  int next() {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    return state;
  }

  final variantIndex = next() % cue.assetPaths.length;
  final volumeUnit = next() / 0x7FFFFFFF;
  final pitchUnit = next() / 0x7FFFFFFF;
  return AudioVariation(
    variantIndex: variantIndex,
    volume: 0.96 + volumeUnit * 0.04,
    pitch: cue.minPitch + (cue.maxPitch - cue.minPitch) * pitchUnit,
  );
}

double clampAudioVolume(double value) => value.clamp(0.0, 1.0).toDouble();

double clampAudioPitch(double value) => value.clamp(0.5, 2.0).toDouble();
