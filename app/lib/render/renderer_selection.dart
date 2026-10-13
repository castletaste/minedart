/// Compile-time renderer selection.
library;

/// The `--dart-define` key used to choose the 3D renderer.
const String kMinedartRendererDefine = 'MINEDART_RENDERER';

/// The renderer used when [kMinedartRendererDefine] is omitted.
const String kDefaultMinedartRenderer = 'flame_3d';

/// Raw compile-time renderer choice.
const String kMinedartRendererValue = String.fromEnvironment(
  kMinedartRendererDefine,
  defaultValue: kDefaultMinedartRenderer,
);

/// Whether this build renders with flutter_scene.
///
/// A const condition, so release builds tree-shake the other renderer's Dart
/// code. Hosts and startup branch on this rather than on [selectedRenderer].
const bool kUsesFlutterScene = kMinedartRendererValue == 'flutter_scene';

enum MinedartRenderer {
  /// flame_3d: WebGPU on web, Flutter GPU natively. The production default.
  flame3d,

  /// flutter_scene: WebGL2 on web, Flutter GPU natively. Experimental.
  flutterScene,
}

/// Parses an explicit renderer value without consulting process state.
///
/// Unsupported values are rejected instead of falling back to another
/// renderer.
MinedartRenderer rendererFromValue(String value) => switch (value) {
  'flame_3d' => MinedartRenderer.flame3d,
  'flutter_scene' => MinedartRenderer.flutterScene,
  _ => throw ArgumentError.value(
    value,
    kMinedartRendererDefine,
    'Unsupported renderer; expected "flame_3d" or "flutter_scene"',
  ),
};

/// The validated compile-time renderer.
///
/// Startup reads this before initializing the GPU, so an invalid define fails
/// before any renderer work.
MinedartRenderer get selectedRenderer =>
    rendererFromValue(kMinedartRendererValue);
