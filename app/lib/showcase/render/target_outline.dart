import 'dart:ui';

import 'package:flame_3d/components.dart';
import 'package:flame_3d/resources.dart';

import '../../render/packed_surface.dart';
import 'packed_primitives.dart';

/// A reusable one-slot target-outline pool for flame_3d 0.3.0.
///
/// The 12 edge cuboids and their [PackedSurface] are built once. Target changes
/// only mutate the retained component's transform, so raycast updates never
/// allocate meshes or vertex objects.
final class TargetOutline extends MeshComponent {
  factory TargetOutline({
    Material? material,
    Color color = const Color(0xFF111111),
    Color highContrastColor = const Color(0xFFFFFF00),
    double thickness = 0.018,
    double padding = 0.003,
  }) {
    if (!thickness.isFinite || thickness <= 0 || thickness >= 0.25) {
      throw ArgumentError.value(
        thickness,
        'thickness',
        'must be finite and between 0 and 0.25',
      );
    }
    if (!padding.isFinite || padding < 0 || padding >= 0.25) {
      throw ArgumentError.value(
        padding,
        'padding',
        'must be finite and between 0 and 0.25',
      );
    }
    final effectiveMaterial = material ?? UnlitMaterial(albedoColor: color);
    final mesh = _outlineGeometry(
      thickness,
      padding,
    ).createMesh(effectiveMaterial);
    return TargetOutline._(
      mesh: mesh,
      material: effectiveMaterial,
      color: color,
      highContrastColor: highContrastColor,
    );
  }

  TargetOutline._({
    required super.mesh,
    required this._material,
    required this.color,
    required this.highContrastColor,
  }) : surface = mesh.surfaces.single as PackedSurface;

  final Material _material;
  final PackedSurface surface;
  final Color color;
  final Color highContrastColor;

  bool enabled = true;
  bool _hasTarget = false;
  bool _highContrast = false;
  int _targetX = 0;
  int _targetY = 0;
  int _targetZ = 0;

  bool get hasTarget => _hasTarget;
  bool get isShown => enabled && _hasTarget;
  bool get highContrast => _highContrast;
  int get targetX => _targetX;
  int get targetY => _targetY;
  int get targetZ => _targetZ;

  /// This remains one for the entire component lifetime.
  int get meshAllocationCount => 1;

  void showAt(int x, int y, int z) {
    _targetX = x;
    _targetY = y;
    _targetZ = z;
    position.setValues(x.toDouble(), y.toDouble(), z.toDouble());
    _hasTarget = true;
  }

  void updateTarget(int x, int y, int z) => showAt(x, y, z);

  void hide() {
    _hasTarget = false;
  }

  void clearTarget() => hide();

  /// Updates the retained unlit material; no shader/material is recreated.
  void setHighContrast(bool value) {
    if (_highContrast == value) return;
    _highContrast = value;
    if (_material case final UnlitMaterial unlit) {
      unlit.albedoColor = value ? highContrastColor : color;
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (!isShown) return;
    super.renderTree(canvas);
  }
}

PackedPrimitiveGeometry _outlineGeometry(double thickness, double padding) {
  final half = thickness / 2;
  final min = -padding;
  final max = 1 + padding;
  return PackedPrimitiveGeometry.cuboids(<PackedCuboid>[
    for (final y in <double>[min, max])
      for (final z in <double>[min, max])
        PackedCuboid(
          minX: min - half,
          minY: y - half,
          minZ: z - half,
          maxX: max + half,
          maxY: y + half,
          maxZ: z + half,
        ),
    for (final x in <double>[min, max])
      for (final z in <double>[min, max])
        PackedCuboid(
          minX: x - half,
          minY: min - half,
          minZ: z - half,
          maxX: x + half,
          maxY: max + half,
          maxZ: z + half,
        ),
    for (final x in <double>[min, max])
      for (final y in <double>[min, max])
        PackedCuboid(
          minX: x - half,
          minY: y - half,
          minZ: min - half,
          maxX: x + half,
          maxY: y + half,
          maxZ: max + half,
        ),
  ]);
}
