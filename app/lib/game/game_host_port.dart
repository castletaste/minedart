import '../showcase/render/render_settings.dart';

/// Typed bridge for events that leave the Flame game and reach its host UI.
///
/// The game keeps one replaceable port instead of exposing a set of nullable
/// callbacks. A host can detach the port in one operation during world
/// replacement or widget teardown.
abstract interface class MinedartGameHostPort {
  void pauseRequested();

  void movementActivity();

  void playerViewChanged();

  void worldChanged();

  void fogPresetChanged(FogPreset preset);
}
