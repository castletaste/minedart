/// Fixed-capacity, deterministic block particle simulation.
///
/// Engine-neutral: renderers read [particles] after [emit] and [update] and
/// copy each slot's transform into their own scene objects.
final class BlockParticleSimulation {
  factory BlockParticleSimulation({
    int capacity = 96,
    int seed = 0x4D445254,
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
    return BlockParticleSimulation._(
      List<BlockParticleState>.generate(
        capacity,
        (_) => BlockParticleState._(),
        growable: false,
      ),
      seed: seed,
      enabled: enabled,
      reducedMotion: reducedMotion,
      gravity: gravity,
    );
  }

  BlockParticleSimulation._(
    List<BlockParticleState> particles, {
    required int seed,
    required this._enabled,
    required this._reducedMotion,
    required this.gravity,
  }) : _particles = particles,
       particles = List<BlockParticleState>.unmodifiable(particles),
       _randomState = _nonZeroSeed(seed);

  final List<BlockParticleState> _particles;
  final List<BlockParticleState> particles;
  final double gravity;

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

  /// Disabling clears active particles.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) clear();
  }

  /// Reduced motion suppresses new bursts and clears active particles.
  set reducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    if (value) clear();
  }

  /// Emits up to [count] particles around ([x], [y], [z]), recycling the
  /// oldest slots, and returns how many were emitted.
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

  /// Advances active particles and retires expired ones.
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

/// One particle slot. A retired slot keeps its last position with zero scale.
final class BlockParticleState {
  BlockParticleState._();

  bool _active = false;
  int _blockId = 0;
  int _serial = 0;
  double _x = 0;
  double _y = 0;
  double _z = 0;
  double _velocityX = 0;
  double _velocityY = 0;
  double _velocityZ = 0;
  double _age = 0;
  double _lifetime = 0;
  double _initialScale = 0;
  double _scale = 0;
  double _spin = 0;

  bool get active => _active;
  int get blockId => _blockId;
  int get serial => _serial;
  double get x => _x;
  double get y => _y;
  double get z => _z;
  double get velocityX => _velocityX;
  double get velocityY => _velocityY;
  double get velocityZ => _velocityZ;
  double get age => _age;
  double get lifetime => _lifetime;

  /// Uniform scale; shrinks linearly to zero over the lifetime.
  double get scale => _scale;

  /// Euler angle (radians) around X; Y and Z use 0.7 and 0.4 of it.
  double get spinAngle => _spin * _age;

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
    _x = x;
    _y = y;
    _z = z;
    _velocityX = velocityX;
    _velocityY = velocityY;
    _velocityZ = velocityZ;
    _age = 0;
    _lifetime = lifetime;
    _initialScale = scale;
    _scale = scale;
    _spin = spin;
  }

  /// Returns true when the particle expired during this step.
  bool _advance(double dt, double gravity) {
    _age += dt;
    if (_age >= _lifetime) {
      _deactivate();
      return true;
    }
    _velocityY -= gravity * dt;
    _x += _velocityX * dt;
    _y += _velocityY * dt;
    _z += _velocityZ * dt;
    _scale = _initialScale * (1 - _age / _lifetime);
    return false;
  }

  void _deactivate() {
    _active = false;
    _blockId = 0;
    _scale = 0;
  }
}

int _nonZeroSeed(int seed) {
  final normalized = seed & 0xFFFFFFFF;
  return normalized == 0 ? 0x6D2B79F5 : normalized;
}
