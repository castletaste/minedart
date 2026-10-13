import 'dart:ui';

import 'package:flame_3d/components.dart';
import 'package:flame_3d/resources.dart';

import '../packed_primitives.dart';
import '../voxel_renderer.dart' show TargetOutlineControls;
import 'packed_surface.dart';

/// A reusable one-slot target-outline pool for flame_3d 0.3.0.
///
/// The 12 edge cuboids and their [PackedSurface] are built once. Target changes
/// only mutate the retained component's transform, so raycast updates never
/// allocate meshes or vertex objects.
final class TargetOutline extends MeshComponent
    implements TargetOutlineControls {
  factory TargetOutline({
    Material? material,
    Color color = const Color(0xFF111111),
    Color highContrastColor = const Color(0xFFFFFF00),
    double thickness = 0.018,
    double padding = 0.003,
  }) {
    final geometry = targetOutlineGeometry(
      thickness: thickness,
      padding: padding,
    );
    final effectiveMaterial = material ?? UnlitMaterial(albedoColor: color);
    final mesh = geometry.createMesh(effectiveMaterial);
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

  @override
  bool enabled = true;
  bool _hasTarget = false;
  bool _highContrast = false;
  int _targetX = 0;
  int _targetY = 0;
  int _targetZ = 0;

  bool get hasTarget => _hasTarget;
  @override
  bool get isShown => enabled && _hasTarget;
  bool get highContrast => _highContrast;
  int get targetX => _targetX;
  int get targetY => _targetY;
  int get targetZ => _targetZ;

  /// This remains one for the entire component lifetime.
  int get meshAllocationCount => 1;

  @override
  void showAt(int x, int y, int z) {
    _targetX = x;
    _targetY = y;
    _targetZ = z;
    position.setValues(x.toDouble(), y.toDouble(), z.toDouble());
    _hasTarget = true;
  }

  void updateTarget(int x, int y, int z) => showAt(x, y, z);

  @override
  void hide() {
    _hasTarget = false;
  }

  void clearTarget() => hide();

  /// Updates the retained unlit material; no shader/material is recreated.
  @override
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
