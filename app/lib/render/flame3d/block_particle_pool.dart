import 'dart:ui';

import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/resources.dart';

import '../block_particle_simulation.dart';
import '../packed_primitives.dart';
import '../voxel_renderer.dart' show BlockParticleEffects;
import 'packed_surface.dart';

/// One retained particle component. Instances are owned by
/// [BlockParticlePool] and are never added or removed while emitting bursts.
final class BlockParticle extends MeshComponent {
  BlockParticle._(Mesh mesh, this._state) : super(mesh: mesh);

  final BlockParticleState _state;

  bool get active => _state.active;
  int get blockId => _state.blockId;
  int get serial => _state.serial;
  double get velocityX => _state.velocityX;
  double get velocityY => _state.velocityY;
  double get velocityZ => _state.velocityZ;
  double get age => _state.age;
  double get lifetime => _state.lifetime;

  void _sync() {
    final scale = _state.scale;
    this.scale.setValues(scale, scale, scale);
    if (!_state.active) return;
    position.setValues(_state.x, _state.y, _state.z);
    final angle = _state.spinAngle;
    rotation.setEuler(angle, angle * 0.7, angle * 0.4);
  }

  @override
  bool isVisible(CameraComponent3D camera) =>
      _state.active && super.isVisible(camera);

  @override
  void renderTree(Canvas canvas) {
    if (!_state.active) return;
    super.renderTree(canvas);
  }
}

/// Fixed-capacity deterministic pool for block-break debris.
///
/// Components and the packed cube mesh are created exactly once. Emission
/// reuses slots in round-robin order; update only mutates retained scalar and
/// transform state. Enabling reduced motion clears the pool and suppresses new
/// bursts. The motion itself lives in [BlockParticleSimulation].
final class BlockParticlePool extends Component3D
    implements BlockParticleEffects {
  factory BlockParticlePool({
    int capacity = 96,
    int seed = 0x4D445254,
    Material? material,
    bool enabled = true,
    bool reducedMotion = false,
    double gravity = 12,
  }) {
    final simulation = BlockParticleSimulation(
      capacity: capacity,
      seed: seed,
      enabled: enabled,
      reducedMotion: reducedMotion,
      gravity: gravity,
    );
    final effectiveMaterial =
        material ?? UnlitMaterial(albedoColor: const Color(0xFFD8C2A2));
    final mesh = unitCubeGeometry.createMesh(effectiveMaterial);
    final particles = List<BlockParticle>.generate(
      capacity,
      (index) => BlockParticle._(mesh, simulation.particles[index]),
      growable: false,
    );
    return BlockParticlePool._(
      simulation: simulation,
      particles: particles,
      mesh: mesh,
    );
  }

  BlockParticlePool._({
    required this._simulation,
    required List<BlockParticle> particles,
    required this.mesh,
  }) : particles = List<BlockParticle>.unmodifiable(particles),
       super(children: particles) {
    _syncAll();
  }

  final BlockParticleSimulation _simulation;
  final List<BlockParticle> particles;
  final Mesh mesh;

  double get gravity => _simulation.gravity;
  int get capacity => _simulation.capacity;
  int get activeCount => _simulation.activeCount;
  int get emittedCount => _simulation.emittedCount;
  @override
  bool get enabled => _simulation.enabled;
  @override
  bool get reducedMotion => _simulation.reducedMotion;

  @override
  set enabled(bool value) {
    _simulation.enabled = value;
    _syncAll();
  }

  @override
  set reducedMotion(bool value) {
    _simulation.reducedMotion = value;
    _syncAll();
  }

  int emit({
    required int blockId,
    required double x,
    required double y,
    required double z,
    int count = 8,
  }) {
    final emitted = _simulation.emit(
      blockId: blockId,
      x: x,
      y: y,
      z: z,
      count: count,
    );
    if (emitted > 0) _syncAll();
    return emitted;
  }

  @override
  int emitBlock({
    required int blockId,
    required int x,
    required int y,
    required int z,
    int count = 8,
  }) =>
      emit(blockId: blockId, x: x + 0.5, y: y + 0.5, z: z + 0.5, count: count);

  int spawn({
    required int blockId,
    required double x,
    required double y,
    required double z,
    int count = 8,
  }) => emit(blockId: blockId, x: x, y: y, z: z, count: count);

  @override
  void update(double dt) {
    if (dt <= 0 || _simulation.activeCount == 0) return;
    _simulation.update(dt);
    _syncAll();
  }

  void clear() {
    _simulation.clear();
    _syncAll();
  }

  void _syncAll() {
    for (var i = 0; i < particles.length; i++) {
      particles[i]._sync();
    }
  }
}
