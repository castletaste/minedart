/// Compile-time texture-atlas selection.
library;

/// The `--dart-define` key used to choose the runtime atlas.
const String kMinedartAtlasDefine = 'MINEDART_ATLAS';

/// The atlas used when [kMinedartAtlasDefine] is omitted.
const String kDefaultMinedartAtlas = 'alpha';

/// Raw compile-time atlas choice.
const String kMinedartAtlasValue = String.fromEnvironment(
  kMinedartAtlasDefine,
  defaultValue: kDefaultMinedartAtlas,
);

enum AtlasVariant { alpha, legacy }

/// A validated runtime atlas and its Flame asset path.
final class AtlasSelection {
  const AtlasSelection({required this.variant, required this.assetPath});

  final AtlasVariant variant;
  final String assetPath;
}

const AtlasSelection kAlphaAtlas = AtlasSelection(
  variant: AtlasVariant.alpha,
  assetPath: 'textures/atlas_alpha.png',
);

const AtlasSelection kLegacyAtlas = AtlasSelection(
  variant: AtlasVariant.legacy,
  assetPath: 'textures/atlas.png',
);

/// Parses an explicit atlas value without consulting process state.
///
/// Unsupported values are rejected instead of falling back to another atlas.
AtlasSelection atlasSelectionFromValue(String value) => switch (value) {
  'alpha' => kAlphaAtlas,
  'legacy' => kLegacyAtlas,
  _ => throw ArgumentError.value(
    value,
    kMinedartAtlasDefine,
    'Unsupported atlas; expected "alpha" or "legacy"',
  ),
};

/// The validated compile-time atlas selection.
///
/// Access this before loading an asset so an invalid define fails clearly.
AtlasSelection get selectedAtlas =>
    atlasSelectionFromValue(kMinedartAtlasValue);
