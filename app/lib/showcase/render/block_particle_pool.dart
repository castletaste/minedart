import 'dart:ui';

import 'package:flame_3d/camera.dart';
import 'package:flame_3d/components.dart';
import 'package:flame_3d/resources.dart';

import 'packed_primitives.dart';

/// One retained particle component. Instances are owned by
/// [BlockParticlePool] and are never added or removed while emitting bursts.
final class BlockParticle extends MeshComponent {
  BlockParticle._(Mesh mesh) : super(mesh: mesh);

  bool _active = false;
  int _blockId = 0;
  int _serial = 0;
  double _velocityX = 0;
  double _velocityY = 0;
  double _velocityZ = 0;
  double _age = 0;
  double _lifetime = 0;
  double _initialScale = 0;
  double _spin = 0;

  bool get active => _active;
  int get blockId => _blockId;
  int get serial => _serial;
  double get velocityX => _velocityX;
  double get velocityY => _velocityY;
  double get velocityZ => _velocityZ;
  double get age => _age;
  double get lifetime => _lifetime;

  void _activate({
    required int blockId,
    required int serial,
    required double x,
    required double y,
    required double z,
    required double velocityX,
    required double velocityY,
    required double velocityZ,
    required double lifetime,
    required double scale,
    required double spin,
  }) {
    _active = true;
    _blockId = blockId;
    _serial = serial;
    _velocityX = velocityX;
    _velocityY = velocityY;
    _velocityZ = velocityZ;
    _age = 0;
    _lifetime = lifetime;
    _initialScale = scale;
    _spin = spin;
    position.setValues(x, y, z);
    this.scale.setValues(scale, scale, scale);
    rotation.setValues(0, 0, 0, 1);
  }

  bool _advance(double dt, double gravity) {
    _age += dt;
    if (_age >= _lifetime) {
      _deactivate();
      return true;
    }
    _velocityY -= gravity * dt;
    position.setValues(
      position.x + _velocityX * dt,
      position.y + _velocityY * dt,
      position.z + _velocityZ * dt,
    );
    final remaining = 1 - _age / _lifetime;
    final currentScale = _initialScale * remaining;
    scale.setValues(currentScale, currentScale, currentScale);
    final angle = _spin * _age;
    rotation.setEuler(angle, angle * 0.7, angle * 0.4);
    return false;
  }

  void _deactivate() {
    _active = false;
    _blockId = 0;
    scale.setValues(0, 0, 0);
  }

  @override
  bool isVisible(CameraComponent3D camera) =>
      _active && super.isVisible(camera);

  @override
  void renderTree(Canvas canvas) {
    if (!_active) return;
    super.renderTree(canvas);
  }
}

/// Fixed-capacity deterministic pool for block-break debris.
///
/// Components and the packed cube mesh are created exactly once. Emission
/// reuses slots in round-robin order; update only mutates retained scalar and
/// transform state. Enabling reduced motion clears the pool and suppresses new
/// bursts.
final class BlockParticlePool extends Component3D {
  factory BlockParticlePool({
    int capacity = 96,
    int seed = 0x4D445254,
    Material? material,
    bool enabled = true,
    bool reducedMotion = false,
    double gravity = 12,
  }) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
    if (!gravity.isFinite || gravity < 0) {
      throw ArgumentError.value(
        gravity,
        'gravity',
        'must be finite and non-negative',
      );
    }
    final effectiveMaterial =
        material ?? UnlitMaterial(albedoColor: const Color(0xFFD8C2A2));
    final mesh = _particleGeometry.createMesh(effectiveMaterial);
    final particles = List<BlockParticle>.generate(
      capacity,
      (_) => BlockParticle._(mesh),
      growable: false,
    );
    return BlockParticlePool._(
      particles: particles,
      seed: seed,
      enabled: enabled,
      reducedMotion: reducedMotion,
      gravity: gravity,
      mesh: mesh,
    );
  }

  BlockParticlePool._({
    required List<BlockParticle> particles,
    required int seed,
    required this._enabled,
    required this._reducedMotion,
    required this.gravity,
    required this.mesh,
  }) : _particles = particles,
       particles = List<BlockParticle>.unmodifiable(particles),
       _randomState = _nonZeroSeed(seed),
       super(children: particles);

  final List<BlockParticle> _particles;
  final List<BlockParticle> particles;
  final double gravity;
  final Mesh mesh;

  bool _enabled;
  bool _reducedMotion;
  int _randomState;
  int _cursor = 0;
  int _activeCount = 0;
  int _serial = 0;

  int get capacity => _particles.length;
  int get activeCount => _activeCount;
  int get emittedCount => _serial;
  bool get enabled => _enabled;
  bool get reducedMotion => _reducedMotion;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) clear();
  }

  set reducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    if (value) clear();
  }

  /// Emits a deterministic burst around a world-space point.
  int emit({
    required int blockId,
    required double x,
    required double y,
    required double z,
    int count = 8,
  }) {
    if (!_enabled || _reducedMotion || count <= 0) return 0;
    if (blockId <= 0 || blockId > 0x0FFF) {
      throw RangeError.range(blockId, 1, 0x0FFF, 'blockId');
    }
    final emitCount = count > capacity ? capacity : count;
    for (var i = 0; i < emitCount; i++) {
      final particle = _particles[_cursor];
      _cursor = (_cursor + 1) % capacity;
      if (!particle.active) _activeCount++;
      _serial++;

      final offsetX = _signedUnit() * 0.28;
      final offsetY = _signedUnit() * 0.22;
      final offsetZ = _signedUnit() * 0.28;
      final velocityX = _signedUnit() * 2.8;
      final velocityY = 2.4 + _nextUnit() * 2.6;
      final velocityZ = _signedUnit() * 2.8;
      final lifetime = 0.45 + _nextUnit() * 0.35;
      final scale = 0.09 + _nextUnit() * 0.08;
      final spin = _signedUnit() * 9;
      particle._activate(
        blockId: blockId,
        serial: _serial,
        x: x + offsetX,
        y: y + offsetY,
        z: z + offsetZ,
        velocityX: velocityX,
        velocityY: velocityY,
        velocityZ: velocityZ,
        lifetime: lifetime,
        scale: scale,
        spin: spin,
      );
    }
    return emitCount;
  }

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
    if (dt <= 0 || _activeCount == 0) return;
    for (var i = 0; i < _particles.length; i++) {
      final particle = _particles[i];
      if (particle.active && particle._advance(dt, gravity)) {
        _activeCount--;
      }
    }
  }

  void clear() {
    if (_activeCount == 0) return;
    for (var i = 0; i < _particles.length; i++) {
      final particle = _particles[i];
      if (particle.active) particle._deactivate();
    }
    _activeCount = 0;
  }

  double _nextUnit() {
    var value = _randomState;
    value ^= (value << 13) & 0xFFFFFFFF;
    value ^= value >>> 17;
    value ^= (value << 5) & 0xFFFFFFFF;
    _randomState = value & 0xFFFFFFFF;
    return (_randomState & 0x00FFFFFF) / 0x01000000;
  }

  double _signedUnit() => _nextUnit() * 2 - 1;
}

int _nonZeroSeed(int seed) {
  final normalized = seed & 0xFFFFFFFF;
  return normalized == 0 ? 0x6D2B79F5 : normalized;
}

final PackedPrimitiveGeometry _particleGeometry =
    PackedPrimitiveGeometry.cuboids(const <PackedCuboid>[
      PackedCuboid(
        minX: -0.5,
        minY: -0.5,
        minZ: -0.5,
        maxX: 0.5,
        maxY: 0.5,
        maxZ: 0.5,
      ),
    ]);
