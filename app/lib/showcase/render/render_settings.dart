import 'package:flutter/foundation.dart';

/// Classic fog distances in world-space blocks.
enum FogPreset {
  near(fogStart: 24, fogEnd: 48),
  normal(fogStart: 48, fogEnd: 96),
  far(fogStart: 96, fogEnd: 160),
  off(fogStart: 1000, fogEnd: 1001);

  const FogPreset({required this.fogStart, required this.fogEnd});

  /// Compatibility names useful to settings UIs.
  static const FogPreset short = near;
  static const FogPreset medium = normal;
  static const FogPreset classic = far;

  final double fogStart;
  final double fogEnd;

  bool get enabled => this != off;

  FogPreset get next => values[(index + 1) % values.length];
}

/// Features that a concrete renderer/backend can actually honor.
enum RenderCapability {
  fog,
  targetOutline,
  blockParticles,
  frameMetrics,
  minimap,
  fieldOfView,
  highContrast,
}

/// Immutable backend capability declaration used by UI and integration code.
@immutable
final class RenderCapabilities {
  const RenderCapabilities({
    this.fog = true,
    this.targetOutline = true,
    this.blockParticles = true,
    this.frameMetrics = true,
    this.minimap = true,
    this.fieldOfView = true,
    this.highContrast = true,
  });

  /// Native Metal path, including the current fog uniforms.
  static const RenderCapabilities native = RenderCapabilities();

  /// WebGPU uses the WGSL voxel material with the same fog control contract.
  static const RenderCapabilities web = RenderCapabilities();

  static const RenderCapabilities all = RenderCapabilities();
  static const RenderCapabilities none = RenderCapabilities(
    fog: false,
    targetOutline: false,
    blockParticles: false,
    frameMetrics: false,
    minimap: false,
    fieldOfView: false,
    highContrast: false,
  );

  final bool fog;
  final bool targetOutline;
  final bool blockParticles;
  final bool frameMetrics;
  final bool minimap;
  final bool fieldOfView;
  final bool highContrast;

  bool supports(RenderCapability capability) => switch (capability) {
    RenderCapability.fog => fog,
    RenderCapability.targetOutline => targetOutline,
    RenderCapability.blockParticles => blockParticles,
    RenderCapability.frameMetrics => frameMetrics,
    RenderCapability.minimap => minimap,
    RenderCapability.fieldOfView => fieldOfView,
    RenderCapability.highContrast => highContrast,
  };
}

/// Immutable settings shared by Render Lab and the game-side renderer bridge.
@immutable
final class RenderSettings {
  const RenderSettings({
    this.fogPreset = FogPreset.far,
    this.targetOutlineEnabled = true,
    this.particlesEnabled = true,
    this.reducedMotion = false,
    this.highContrast = false,
    this.frameGraphEnabled = false,
    this.fieldOfViewDegrees = 70,
  }) : assert(
         fieldOfViewDegrees >= minFieldOfViewDegrees &&
             fieldOfViewDegrees <= maxFieldOfViewDegrees,
       );

  static const double minFieldOfViewDegrees = 30;
  static const double maxFieldOfViewDegrees = 110;
  static const RenderSettings defaults = RenderSettings();

  final FogPreset fogPreset;
  final bool targetOutlineEnabled;
  final bool particlesEnabled;
  final bool reducedMotion;
  final bool highContrast;
  final bool frameGraphEnabled;
  final double fieldOfViewDegrees;

  /// Accessibility motion reduction suppresses transient block particles while
  /// retaining the user's normal particle preference.
  bool get particlesActive => particlesEnabled && !reducedMotion;

  RenderSettings copyWith({
    FogPreset? fogPreset,
    bool? targetOutlineEnabled,
    bool? particlesEnabled,
    bool? reducedMotion,
    bool? highContrast,
    bool? frameGraphEnabled,
    double? fieldOfViewDegrees,
  }) => RenderSettings(
    fogPreset: fogPreset ?? this.fogPreset,
    targetOutlineEnabled: targetOutlineEnabled ?? this.targetOutlineEnabled,
    particlesEnabled: particlesEnabled ?? this.particlesEnabled,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    highContrast: highContrast ?? this.highContrast,
    frameGraphEnabled: frameGraphEnabled ?? this.frameGraphEnabled,
    fieldOfViewDegrees: fieldOfViewDegrees ?? this.fieldOfViewDegrees,
  );

  /// Produces settings that never advertise an unsupported active feature.
  RenderSettings resolvedFor(RenderCapabilities capabilities) => copyWith(
    fogPreset: capabilities.fog ? fogPreset : FogPreset.off,
    targetOutlineEnabled: capabilities.targetOutline && targetOutlineEnabled,
    particlesEnabled: capabilities.blockParticles && particlesEnabled,
    highContrast: capabilities.highContrast && highContrast,
    frameGraphEnabled: capabilities.frameMetrics && frameGraphEnabled,
    fieldOfViewDegrees: capabilities.fieldOfView
        ? fieldOfViewDegrees
        : defaults.fieldOfViewDegrees,
  );

  @override
  bool operator ==(Object other) =>
      other is RenderSettings &&
      other.fogPreset == fogPreset &&
      other.targetOutlineEnabled == targetOutlineEnabled &&
      other.particlesEnabled == particlesEnabled &&
      other.reducedMotion == reducedMotion &&
      other.highContrast == highContrast &&
      other.frameGraphEnabled == frameGraphEnabled &&
      other.fieldOfViewDegrees == fieldOfViewDegrees;

  @override
  int get hashCode => Object.hash(
    fogPreset,
    targetOutlineEnabled,
    particlesEnabled,
    reducedMotion,
    highContrast,
    frameGraphEnabled,
    fieldOfViewDegrees,
  );
}
