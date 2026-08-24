import 'package:flutter/foundation.dart';

enum RenderDebugView {
  lit('Lit', 0),
  albedo('Albedo', 1),
  normals('Normals', 2),
  bakedLighting('Baked lighting + AO', 3),
  chunkBorders('Chunk borders', 5);

  const RenderDebugView(this.label, this.shaderCode);

  final String label;
  final int shaderCode;
}

enum TextureFiltering {
  nearest('Nearest'),
  linear('Linear');

  const TextureFiltering(this.label);

  final String label;
}

@immutable
final class RenderLabSettings {
  const RenderLabSettings({
    this.debugView = RenderDebugView.lit,
    this.filtering = TextureFiltering.nearest,
    this.renderDistance = 6,
    this.fogDensity = 0.55,
    this.ambientOcclusion = true,
    this.targetOutline = true,
    this.blockParticles = true,
  });

  final RenderDebugView debugView;
  final TextureFiltering filtering;
  final int renderDistance;
  final double fogDensity;
  final bool ambientOcclusion;
  final bool targetOutline;
  final bool blockParticles;

  RenderLabSettings copyWith({
    RenderDebugView? debugView,
    TextureFiltering? filtering,
    int? renderDistance,
    double? fogDensity,
    bool? ambientOcclusion,
    bool? targetOutline,
    bool? blockParticles,
  }) => RenderLabSettings(
    debugView: debugView ?? this.debugView,
    filtering: filtering ?? this.filtering,
    renderDistance: renderDistance ?? this.renderDistance,
    fogDensity: fogDensity ?? this.fogDensity,
    ambientOcclusion: ambientOcclusion ?? this.ambientOcclusion,
    targetOutline: targetOutline ?? this.targetOutline,
    blockParticles: blockParticles ?? this.blockParticles,
  );
}

/// Typed Render Lab settings only. The renderer owns all material/uniform work.
final class RenderLabController extends ChangeNotifier {
  factory RenderLabController({
    RenderLabSettings settings = const RenderLabSettings(),
    ValueChanged<RenderLabSettings>? onChanged,
  }) => RenderLabController._(settings: settings, onChanged: onChanged);

  RenderLabController._({required this._settings, this.onChanged});

  RenderLabSettings _settings;
  final ValueChanged<RenderLabSettings>? onChanged;

  RenderLabSettings get settings => _settings;

  void setDebugView(RenderDebugView value) =>
      _set(_settings.copyWith(debugView: value));

  void setFiltering(TextureFiltering value) =>
      _set(_settings.copyWith(filtering: value));

  void setRenderDistance(double value) =>
      _set(_settings.copyWith(renderDistance: value.round().clamp(2, 16)));

  void setFogDensity(double value) =>
      _set(_settings.copyWith(fogDensity: value.clamp(0.0, 1.0)));

  void setAmbientOcclusion(bool value) =>
      _set(_settings.copyWith(ambientOcclusion: value));

  void setTargetOutline(bool value) =>
      _set(_settings.copyWith(targetOutline: value));

  void setBlockParticles(bool value) =>
      _set(_settings.copyWith(blockParticles: value));

  void reset() => _set(const RenderLabSettings());

  void _set(RenderLabSettings value) {
    _settings = value;
    onChanged?.call(value);
    notifyListeners();
  }
}
