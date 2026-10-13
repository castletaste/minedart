import '../audio/audio.dart';

typedef WorldRemeshObserver = void Function(Set<int> dirtyChunks);
typedef WorldParticleObserver =
    void Function({
      required int blockId,
      required int x,
      required int y,
      required int z,
      int count,
    });
typedef WorldAudioObserver = void Function(AudioCue cue, {int seed});

/// Side effects emitted by world interaction, kept outside the simulation.
abstract interface class WorldEffects {
  void remesh(Set<int> dirtyChunks);

  void particle({
    required int blockId,
    required int x,
    required int y,
    required int z,
    int count,
  });

  void audio(AudioCue cue, {int seed});
}

/// Adapter for wiring the interaction controller to the game shell.
final class CallbackWorldEffects implements WorldEffects {
  const CallbackWorldEffects({
    required this.onRemesh,
    required this.onParticle,
    required this.onAudio,
  });

  final WorldRemeshObserver onRemesh;
  final WorldParticleObserver onParticle;
  final WorldAudioObserver onAudio;

  @override
  void remesh(Set<int> dirtyChunks) => onRemesh(dirtyChunks);

  @override
  void particle({
    required int blockId,
    required int x,
    required int y,
    required int z,
    int count = 8,
  }) => onParticle(blockId: blockId, x: x, y: y, z: z, count: count);

  @override
  void audio(AudioCue cue, {int seed = 0}) => onAudio(cue, seed: seed);
}
