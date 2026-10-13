import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/game/replay.dart';

void main() {
  test('replay recording canonicalizes keys and round-trips JSON', () {
    final recorder = ReplayRecorder(seed: 17)
      ..record(
        dt: const Duration(microseconds: 16667),
        keys: <int>[40, 12, 40],
        lookDx: 2.5,
        touchForward: 1,
        breakRequests: 1,
      )
      ..record(dt: const Duration(microseconds: 16667), touchJump: true);

    final trace = recorder.finish();
    final decoded = ReplayTrace.decode(trace.encode());

    expect(decoded.seed, 17);
    expect(decoded.frames, trace.frames);
    expect(decoded.frames.first.keys, <int>[12, 40]);
  });

  test('replay player is repeatable and rejects non-monotonic traces', () {
    final trace = ReplayTrace(
      seed: 1,
      frames: const <ReplayInputFrame>[
        ReplayInputFrame(tick: 0, dtMicros: 1, keys: <int>[]),
        ReplayInputFrame(tick: 1, dtMicros: 1, keys: <int>[]),
      ],
    );
    final player = ReplayPlayer(trace);

    expect(player.next()?.tick, 0);
    expect(player.next()?.tick, 1);
    expect(player.next(), isNull);
    expect(player.isComplete, isTrue);
    player.reset();
    expect(player.next()?.tick, 0);

    expect(
      () => ReplayTrace.decode(
        '{"version":1,"seed":1,"frames":['
        '{"tick":1,"dtMicros":1,"keys":[],"lookDx":0,"lookDy":0,'
        '"touchForward":0,"touchStrafe":0,"touchJump":false,'
        '"touchSprint":false,"breakRequests":0,"placeRequests":0},'
        '{"tick":1,"dtMicros":1,"keys":[],"lookDx":0,"lookDy":0,'
        '"touchForward":0,"touchStrafe":0,"touchJump":false,'
        '"touchSprint":false,"breakRequests":0,"placeRequests":0}]}',
      ),
      throwsFormatException,
    );
  });

  test('replay runner applies the same command trace deterministically', () {
    final trace = ReplayTrace(
      seed: 9,
      frames: const <ReplayInputFrame>[
        ReplayInputFrame(tick: 0, dtMicros: 10, keys: <int>[1]),
        ReplayInputFrame(tick: 1, dtMicros: 20, keys: <int>[2, 3]),
      ],
    );
    int step(int state, ReplayInputFrame frame) =>
        state + frame.dtMicros + frame.keys.fold(0, (sum, key) => sum + key);
    final runner = DeterministicTraceRunner<int>(trace);

    expect(runner.run(initialState: 0, step: step), 36);
    expect(runner.run(initialState: 0, step: step), 36);
  });
}
