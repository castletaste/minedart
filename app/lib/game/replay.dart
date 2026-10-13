import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A complete input sample captured at one simulation boundary.
///
/// The format is deliberately JSON so a failing run can be attached to an
/// issue and replayed without depending on Flutter or Flame internals.
@immutable
final class ReplayInputFrame {
  const ReplayInputFrame({
    required this.tick,
    required this.dtMicros,
    required this.keys,
    this.lookDx = 0,
    this.lookDy = 0,
    this.touchForward = 0,
    this.touchStrafe = 0,
    this.touchJump = false,
    this.touchSprint = false,
    this.breakRequests = 0,
    this.placeRequests = 0,
  });

  final int tick;
  final int dtMicros;
  final List<int> keys;
  final double lookDx;
  final double lookDy;
  final double touchForward;
  final double touchStrafe;
  final bool touchJump;
  final bool touchSprint;
  final int breakRequests;
  final int placeRequests;

  Map<String, Object> toJson() => <String, Object>{
    'tick': tick,
    'dtMicros': dtMicros,
    'keys': keys,
    'lookDx': lookDx,
    'lookDy': lookDy,
    'touchForward': touchForward,
    'touchStrafe': touchStrafe,
    'touchJump': touchJump,
    'touchSprint': touchSprint,
    'breakRequests': breakRequests,
    'placeRequests': placeRequests,
  };

  factory ReplayInputFrame.fromJson(Map<String, Object?> json) {
    final keys = json['keys'];
    if (keys is! List || keys.any((key) => key is! int)) {
      throw const FormatException('Replay keys are invalid');
    }
    final frame = ReplayInputFrame(
      tick: _int(json['tick'], 'tick'),
      dtMicros: _int(json['dtMicros'], 'dtMicros'),
      keys: List<int>.unmodifiable(keys.cast<int>()),
      lookDx: _double(json['lookDx'], 'lookDx'),
      lookDy: _double(json['lookDy'], 'lookDy'),
      touchForward: _double(json['touchForward'], 'touchForward'),
      touchStrafe: _double(json['touchStrafe'], 'touchStrafe'),
      touchJump: _bool(json['touchJump'], 'touchJump'),
      touchSprint: _bool(json['touchSprint'], 'touchSprint'),
      breakRequests: _int(json['breakRequests'], 'breakRequests'),
      placeRequests: _int(json['placeRequests'], 'placeRequests'),
    );
    if (frame.tick < 0 ||
        frame.dtMicros <= 0 ||
        frame.breakRequests < 0 ||
        frame.placeRequests < 0) {
      throw const FormatException('Replay timing is invalid');
    }
    return frame;
  }

  @override
  bool operator ==(Object other) =>
      other is ReplayInputFrame &&
      other.tick == tick &&
      other.dtMicros == dtMicros &&
      listEquals(other.keys, keys) &&
      other.lookDx == lookDx &&
      other.lookDy == lookDy &&
      other.touchForward == touchForward &&
      other.touchStrafe == touchStrafe &&
      other.touchJump == touchJump &&
      other.touchSprint == touchSprint &&
      other.breakRequests == breakRequests &&
      other.placeRequests == placeRequests;

  @override
  int get hashCode => Object.hash(
    tick,
    dtMicros,
    Object.hashAll(keys),
    lookDx,
    lookDy,
    touchForward,
    touchStrafe,
    touchJump,
    touchSprint,
    breakRequests,
    placeRequests,
  );
}

@immutable
final class ReplayTrace {
  const ReplayTrace({required this.seed, required this.frames});

  final int seed;
  final List<ReplayInputFrame> frames;

  String encode() => jsonEncode(<String, Object>{
    'version': 1,
    'seed': seed,
    'frames': frames.map((frame) => frame.toJson()).toList(growable: false),
  });

  factory ReplayTrace.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('Unsupported replay version');
    }
    final frames = decoded['frames'];
    if (frames is! List) throw const FormatException('Replay frames missing');
    final parsed = <ReplayInputFrame>[];
    var previousTick = -1;
    for (final raw in frames) {
      if (raw is! Map) throw const FormatException('Replay frame is invalid');
      final frame = ReplayInputFrame.fromJson(Map<String, Object?>.from(raw));
      if (frame.tick <= previousTick) {
        throw const FormatException('Replay ticks are not increasing');
      }
      previousTick = frame.tick;
      parsed.add(frame);
    }
    return ReplayTrace(
      seed: _int(decoded['seed'], 'seed'),
      frames: List<ReplayInputFrame>.unmodifiable(parsed),
    );
  }
}

/// Records immutable frame inputs with monotonically increasing ticks.
final class ReplayRecorder {
  ReplayRecorder({required this.seed});

  final int seed;
  final List<ReplayInputFrame> _frames = <ReplayInputFrame>[];
  bool _finished = false;

  int get length => _frames.length;

  void record({
    required Duration dt,
    Iterable<int> keys = const <int>[],
    double lookDx = 0,
    double lookDy = 0,
    double touchForward = 0,
    double touchStrafe = 0,
    bool touchJump = false,
    bool touchSprint = false,
    int breakRequests = 0,
    int placeRequests = 0,
  }) {
    if (_finished) throw StateError('Replay recorder is finished');
    final dtMicros = dt.inMicroseconds;
    if (dtMicros <= 0) throw ArgumentError.value(dt, 'dt');
    final canonicalKeys = keys.toSet().toList()..sort();
    _frames.add(
      ReplayInputFrame(
        tick: _frames.length,
        dtMicros: dtMicros,
        keys: List<int>.unmodifiable(canonicalKeys),
        lookDx: _finite(lookDx, 'lookDx'),
        lookDy: _finite(lookDy, 'lookDy'),
        touchForward: _finite(touchForward, 'touchForward'),
        touchStrafe: _finite(touchStrafe, 'touchStrafe'),
        touchJump: touchJump,
        touchSprint: touchSprint,
        breakRequests: breakRequests,
        placeRequests: placeRequests,
      ),
    );
  }

  ReplayTrace finish() {
    _finished = true;
    return ReplayTrace(seed: seed, frames: List.unmodifiable(_frames));
  }
}

/// Advances a trace without mutating it, making deterministic test runners
/// straightforward to write.
final class ReplayPlayer {
  ReplayPlayer(this.trace);

  final ReplayTrace trace;
  int _index = 0;

  int get index => _index;
  bool get isComplete => _index == trace.frames.length;

  ReplayInputFrame? next() {
    if (isComplete) return null;
    return trace.frames[_index++];
  }

  void reset() => _index = 0;
}

/// Applies every recorded input to a caller-owned deterministic state.
///
/// This is a trace reducer, not a complete game playback system. It has no
/// Flutter or Flame dependency; callers provide the state transition.
final class DeterministicTraceRunner<T> {
  const DeterministicTraceRunner(this.trace);

  final ReplayTrace trace;

  T run({
    required T initialState,
    required T Function(T, ReplayInputFrame) step,
  }) {
    var state = initialState;
    for (final frame in trace.frames) {
      state = step(state, frame);
    }
    return state;
  }
}

int _int(Object? value, String name) {
  if (value is int) return value;
  throw FormatException('Replay $name is invalid');
}

double _double(Object? value, String name) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('Replay $name is invalid');
}

bool _bool(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('Replay $name is invalid');
}

double _finite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name);
  return value;
}
