import 'package:flame_3d/camera.dart';
import 'package:flutter/foundation.dart';

import '../../render/voxel_material.dart';
import 'block_particle_pool.dart';
import 'frame_metrics.dart';
import 'render_settings.dart';
import 'target_outline.dart';

/// Typed target for an already-created material's fog uniforms.
abstract interface class FogUniformTarget {
  void applyFog(FogPreset preset);
}

/// Adapter for the canonical native voxel material. It mutates uniforms only;
/// it never replaces a shader or material instance.
final class VoxelMaterialFogTarget implements FogUniformTarget {
  const VoxelMaterialFogTarget(this.material);

  final VoxelMaterialControls material;

  @override
  void applyFog(FogPreset preset) {
    material.setFogRange(preset.fogStart, preset.fogEnd);
  }
}

/// Commands accepted by [RenderLabBridge]. No map/string protocol crosses the
/// UI-to-renderer boundary.
sealed class RenderLabCommand {
  const RenderLabCommand();
}

final class SetFogPreset extends RenderLabCommand {
  const SetFogPreset(this.preset);
  final FogPreset preset;
}

final class CycleFogPreset extends RenderLabCommand {
  const CycleFogPreset();
}

final class SetTargetOutlineEnabled extends RenderLabCommand {
  const SetTargetOutlineEnabled(this.enabled);
  final bool enabled;
}

final class SetBlockParticlesEnabled extends RenderLabCommand {
  const SetBlockParticlesEnabled(this.enabled);
  final bool enabled;
}

final class SetReducedMotion extends RenderLabCommand {
  const SetReducedMotion(this.enabled);
  final bool enabled;
}

final class SetHighContrast extends RenderLabCommand {
  const SetHighContrast(this.enabled);
  final bool enabled;
}

final class SetFrameGraphEnabled extends RenderLabCommand {
  const SetFrameGraphEnabled(this.enabled);
  final bool enabled;
}

final class SetFieldOfView extends RenderLabCommand {
  const SetFieldOfView(this.degrees);
  final double degrees;
}

enum RenderLabUpdateStatus { applied, unchanged, unsupported }

@immutable
final class RenderLabUpdateResult {
  const RenderLabUpdateResult({
    required this.status,
    required this.settings,
    this.unsupportedCapability,
  });

  final RenderLabUpdateStatus status;
  final RenderSettings settings;
  final RenderCapability? unsupportedCapability;

  bool get changed => status == RenderLabUpdateStatus.applied;
}

/// UI-facing typed bridge to retained renderer state.
///
/// Settings are capability-resolved before application. Existing material
/// uniforms, component flags, and camera fields are mutated in place; the game
/// widget, meshes, shaders, and material instances are not rebuilt.
final class RenderLabBridge extends ChangeNotifier {
  RenderLabBridge({
    required this.capabilities,
    RenderSettings initialSettings = RenderSettings.defaults,
    this.fogTarget,
    this.targetOutline,
    this.particlePool,
    this.camera,
    FrameMetrics? frameMetrics,
  }) : frameMetrics = frameMetrics ?? FrameMetrics(),
       _settings = initialSettings.resolvedFor(capabilities) {
    _applyToTargets();
  }

  final RenderCapabilities capabilities;
  final FogUniformTarget? fogTarget;
  final TargetOutline? targetOutline;
  final BlockParticlePool? particlePool;
  final CameraComponent3D? camera;
  final FrameMetrics frameMetrics;

  RenderSettings _settings;
  RenderSettings get settings => _settings;

  RenderLabUpdateResult dispatch(RenderLabCommand command) => switch (command) {
    SetFogPreset(:final preset) => setFogPreset(preset),
    CycleFogPreset() => cycleFogPreset(),
    SetTargetOutlineEnabled(:final enabled) => setTargetOutlineEnabled(enabled),
    SetBlockParticlesEnabled(:final enabled) => setBlockParticlesEnabled(
      enabled,
    ),
    SetReducedMotion(:final enabled) => setReducedMotion(enabled),
    SetHighContrast(:final enabled) => setHighContrast(enabled),
    SetFrameGraphEnabled(:final enabled) => setFrameGraphEnabled(enabled),
    SetFieldOfView(:final degrees) => setFieldOfView(degrees),
  };

  RenderLabUpdateResult applySettings(RenderSettings settings) {
    final resolved = settings.resolvedFor(capabilities);
    return _commit(resolved);
  }

  RenderLabUpdateResult setFogPreset(FogPreset preset) {
    if (!capabilities.fog && preset != FogPreset.off) {
      return _unsupported(RenderCapability.fog);
    }
    return _commit(_settings.copyWith(fogPreset: preset));
  }

  RenderLabUpdateResult cycleFogPreset() =>
      setFogPreset(_settings.fogPreset.next);

  RenderLabUpdateResult setTargetOutlineEnabled(bool enabled) {
    if (!capabilities.targetOutline && enabled) {
      return _unsupported(RenderCapability.targetOutline);
    }
    return _commit(_settings.copyWith(targetOutlineEnabled: enabled));
  }

  RenderLabUpdateResult setBlockParticlesEnabled(bool enabled) {
    if (!capabilities.blockParticles && enabled) {
      return _unsupported(RenderCapability.blockParticles);
    }
    return _commit(_settings.copyWith(particlesEnabled: enabled));
  }

  RenderLabUpdateResult setReducedMotion(bool enabled) =>
      _commit(_settings.copyWith(reducedMotion: enabled));

  RenderLabUpdateResult setHighContrast(bool enabled) {
    if (!capabilities.highContrast && enabled) {
      return _unsupported(RenderCapability.highContrast);
    }
    return _commit(_settings.copyWith(highContrast: enabled));
  }

  RenderLabUpdateResult setFrameGraphEnabled(bool enabled) {
    if (!capabilities.frameMetrics && enabled) {
      return _unsupported(RenderCapability.frameMetrics);
    }
    return _commit(_settings.copyWith(frameGraphEnabled: enabled));
  }

  RenderLabUpdateResult setFieldOfView(double degrees) {
    if (!degrees.isFinite ||
        degrees < RenderSettings.minFieldOfViewDegrees ||
        degrees > RenderSettings.maxFieldOfViewDegrees) {
      throw ArgumentError.value(
        degrees,
        'degrees',
        'must be between ${RenderSettings.minFieldOfViewDegrees} and '
            '${RenderSettings.maxFieldOfViewDegrees}',
      );
    }
    if (!capabilities.fieldOfView) {
      return _unsupported(RenderCapability.fieldOfView);
    }
    return _commit(_settings.copyWith(fieldOfViewDegrees: degrees));
  }

  void recordFrame({
    required double frameTimeMs,
    double updateTimeMs = 0,
    double renderTimeMs = 0,
    double meshTimeMs = 0,
  }) {
    frameMetrics.record(
      frameTimeMs: frameTimeMs,
      updateTimeMs: updateTimeMs,
      renderTimeMs: renderTimeMs,
      meshTimeMs: meshTimeMs,
    );
  }

  RenderLabUpdateResult _commit(RenderSettings next) {
    final resolved = next.resolvedFor(capabilities);
    if (_settings == resolved) {
      return RenderLabUpdateResult(
        status: RenderLabUpdateStatus.unchanged,
        settings: _settings,
      );
    }
    _settings = resolved;
    _applyToTargets();
    notifyListeners();
    return RenderLabUpdateResult(
      status: RenderLabUpdateStatus.applied,
      settings: _settings,
    );
  }

  RenderLabUpdateResult _unsupported(RenderCapability capability) =>
      RenderLabUpdateResult(
        status: RenderLabUpdateStatus.unsupported,
        settings: _settings,
        unsupportedCapability: capability,
      );

  void _applyToTargets() {
    fogTarget?.applyFog(_settings.fogPreset);
    final outline = targetOutline;
    if (outline != null) {
      outline
        ..enabled = _settings.targetOutlineEnabled
        ..setHighContrast(_settings.highContrast);
    }
    final particles = particlePool;
    if (particles != null) {
      particles
        ..reducedMotion = _settings.reducedMotion
        ..enabled = _settings.particlesEnabled;
    }
    if (capabilities.fieldOfView) {
      camera?.fovY = _settings.fieldOfViewDegrees;
    }
  }
}
