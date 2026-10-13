import 'flame3d/flame3d_voxel_renderer.dart' show initializeFlame3dGpu;
import 'flutter_scene/scene_voxel_renderer.dart' show initializeFlutterSceneGpu;
import 'renderer_selection.dart';

/// Initializes the compile-time renderer's GPU stack.
///
/// Validates `MINEDART_RENDERER` first, so an unsupported value fails before
/// any renderer work. Failures surface as `RendererInitializationException`.
Future<void> initializeSelectedRenderer() {
  selectedRenderer;
  return kUsesFlutterScene
      ? initializeFlutterSceneGpu()
      : initializeFlame3dGpu();
}

/// The graphics API named in startup guidance when it is unavailable.
const String kSelectedRendererApiName = kUsesFlutterScene
    ? 'WebGL 2'
    : 'WebGPU';
