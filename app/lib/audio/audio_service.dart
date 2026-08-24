import 'package:audioplayers/audioplayers.dart';

import 'audio_cue.dart';

/// Small seam around audioplayers so service lifecycle can be tested without
/// starting a platform audio engine.
abstract interface class AudioPoolBackend {
  Future<void> play({
    required AudioCue cue,
    required int variantIndex,
    required double volume,
    required double pitch,
  });

  Future<void> dispose();
}

/// Production backend backed by one bounded [AudioPool] per cue asset.
final class AudioplayersPoolBackend implements AudioPoolBackend {
  AudioplayersPoolBackend._(this._pools);

  final Map<String, AudioPool> _pools;
  bool _disposed = false;

  static Future<AudioplayersPoolBackend> create({int maxPlayers = 8}) async {
    if (maxPlayers < 1) {
      throw ArgumentError.value(maxPlayers, 'maxPlayers', 'must be positive');
    }
    final pools = <String, AudioPool>{};
    try {
      final assetPaths = <String>{
        for (final cue in AudioCue.values) ...cue.assetPaths,
      };
      for (final assetPath in assetPaths) {
        pools[assetPath] = await AudioPool.createFromAsset(
          path: assetPath,
          minPlayers: 1,
          maxPlayers: maxPlayers,
        );
      }
      return AudioplayersPoolBackend._(pools);
    } catch (_) {
      await Future.wait(pools.values.map((pool) => pool.dispose()));
      rethrow;
    }
  }

  @override
  Future<void> play({
    required AudioCue cue,
    required int variantIndex,
    required double volume,
    required double pitch,
  }) async {
    if (_disposed) return;
    final pool = _pools[cue.assetPathFor(variantIndex)]!;
    // AudioPool's currentPlayers is intentionally visible for test support;
    // it is the only public way to reach the player reserved by start().
    // ignore: invalid_use_of_visible_for_testing_member
    final before = pool.currentPlayers.keys.toSet();
    await pool.start(volume: volume);

    // AudioPool.start intentionally exposes only a stop callback. Its public
    // currentPlayers map lets us apply the per-invocation pitch to the player
    // that was just reserved, while AudioPool still owns bounded reuse and
    // completion cleanup.
    // ignore: invalid_use_of_visible_for_testing_member
    // ignore: invalid_use_of_visible_for_testing_member
    final activePlayers = pool.currentPlayers.entries.toList();
    final player = activePlayers
        .firstWhere(
          (entry) => !before.contains(entry.key),
          orElse: () => activePlayers.last,
        )
        .value;
    await player.setPlaybackRate(pitch);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(_pools.values.map((pool) => pool.dispose()));
  }
}

/// Common integration surface shared by real and no-op services.
abstract interface class AudioServiceApi {
  double get sfxVolume;
  double get musicVolume;
  bool get muted;
  bool get isDisposed;

  Future<void> setSfxVolume(double value);
  Future<void> setMusicVolume(double value);
  Future<void> setMuted(bool value);
  Future<void> play(AudioCue cue, {int seed, double volume});
  Future<void> dispose();
}

/// Audio service used by the game integration.
final class AudioService implements AudioServiceApi {
  AudioService._(this._backend, {this.maxSfxVolume = 1.0})
    : _sfxVolume = clampAudioVolume(maxSfxVolume);

  /// Creates the platform-backed service and preloads one player per cue.
  static Future<AudioService> create({
    int maxPlayers = 8,
    double maxSfxVolume = 1.0,
  }) async {
    return AudioService._(
      await AudioplayersPoolBackend.create(maxPlayers: maxPlayers),
      maxSfxVolume: maxSfxVolume,
    );
  }

  /// Creates a service with a test or platform-specific backend.
  factory AudioService.withBackend(
    AudioPoolBackend backend, {
    double maxSfxVolume = 1.0,
  }) {
    return AudioService._(backend, maxSfxVolume: maxSfxVolume);
  }

  final AudioPoolBackend _backend;
  final double maxSfxVolume;
  double _sfxVolume;
  double _musicVolume = 1.0;
  bool _muted = false;
  bool _disposed = false;

  @override
  double get sfxVolume => _sfxVolume;
  @override
  double get musicVolume => _musicVolume;
  @override
  bool get muted => _muted;
  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> setSfxVolume(double value) async {
    _sfxVolume = clampAudioVolume(value);
  }

  @override
  Future<void> setMusicVolume(double value) async {
    _musicVolume = clampAudioVolume(value);
  }

  @override
  Future<void> setMuted(bool value) async {
    _muted = value;
  }

  /// Plays one short SFX with deterministic volume and pitch variation.
  @override
  Future<void> play(AudioCue cue, {int seed = 0, double volume = 1.0}) async {
    if (_disposed || _muted) return;
    final variation = audioVariation(cue, seed);
    final effectiveVolume = clampAudioVolume(
      variation.volume * cue.baseVolume * _sfxVolume * volume,
    );
    if (effectiveVolume == 0) return;
    await _backend.play(
      cue: cue,
      variantIndex: variation.variantIndex,
      volume: effectiveVolume,
      pitch: clampAudioPitch(variation.pitch),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _backend.dispose();
  }
}

/// No-op implementation for tests and unsupported platforms.
final class NullAudioService implements AudioServiceApi {
  const NullAudioService();

  @override
  double get sfxVolume => 1.0;
  @override
  double get musicVolume => 1.0;
  @override
  bool get muted => true;
  @override
  bool get isDisposed => false;

  @override
  Future<void> setSfxVolume(double value) async {}
  @override
  Future<void> setMusicVolume(double value) async {}
  @override
  Future<void> setMuted(bool value) async {}
  @override
  Future<void> play(AudioCue cue, {int seed = 0, double volume = 1.0}) async {}
  @override
  Future<void> dispose() async {}
}
