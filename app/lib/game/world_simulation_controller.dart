import 'package:minedart_core/minedart_core.dart';

typedef WorldSimulationChangeObserver = void Function(WorldChangeSet changes);

/// Owns deterministic block simulation and its undo/redo boundaries.
final class WorldSimulationController {
  WorldSimulationController({
    required this.world,
    WorldTickEngine? ticks,
    EditHistory? history,
    this.tickStep = 0.05,
    this.tickBudget = 256,
    this.maxStepsPerAdvance = 5,
    this.onChanges,
  }) : ticks = ticks ?? WorldTickEngine(),
       history = history ?? EditHistory() {
    if (!tickStep.isFinite || tickStep <= 0) {
      throw ArgumentError.value(
        tickStep,
        'tickStep',
        'must be finite and positive',
      );
    }
    if (tickBudget <= 0) {
      throw ArgumentError.value(tickBudget, 'tickBudget', 'must be positive');
    }
    if (maxStepsPerAdvance <= 0) {
      throw ArgumentError.value(
        maxStepsPerAdvance,
        'maxStepsPerAdvance',
        'must be positive',
      );
    }
  }

  final VoxelWorld world;
  final WorldTickEngine ticks;
  final EditHistory history;
  final double tickStep;
  final int tickBudget;
  final int maxStepsPerAdvance;
  final WorldSimulationChangeObserver? onChanges;

  double _accumulator = 0;
  bool _suppressPrimedHistory = false;

  /// Arms work encoded in a freshly loaded world without recording it as an
  /// edit made by the player.
  void initialize() {
    ticks.prime(world);
    _suppressPrimedHistory = !ticks.isIdle;
  }

  /// Records one direct player edit and schedules its deterministic cascade.
  void recordUserEdit(WorldChangeSet? changes) {
    if (changes == null || changes.isEmpty) return;
    beginUserCascade();
    history.record(changes);
    for (final change in changes.changes) {
      ticks.enqueueAround(change.x, change.y, change.z);
    }
  }

  /// Starts a new player-owned undo group.
  ///
  /// A player edit becomes the history boundary even if load reconvergence is
  /// still pending. Its later simulation changes belong to this new cascade.
  void beginUserCascade() {
    _suppressPrimedHistory = false;
    history.beginGroup();
  }

  /// Advances at most [maxStepsPerAdvance] fixed ticks.
  ///
  /// Non-finite and non-positive frame deltas are ignored so a bad platform
  /// timestamp cannot poison the accumulator.
  ///
  /// The observer receives non-empty world changes so the game can own render,
  /// particle, audio, and HUD effects without owning simulation state.
  void advance(double dt) {
    if (!dt.isFinite || dt <= 0) return;
    _accumulator += dt.clamp(0, 0.25);
    var steps = 0;
    while (_accumulator >= tickStep && steps < maxStepsPerAdvance) {
      _accumulator -= tickStep;
      steps++;
      final changes = ticks.tick(world, tickBudget);
      if (changes.isNotEmpty) {
        if (!_suppressPrimedHistory) history.record(changes);
        onChanges?.call(changes);
      }
      if (ticks.isIdle) {
        _suppressPrimedHistory = false;
        history.endGroup();
      }
    }
  }

  WorldChangeSet undo() {
    final changes = history.undo(world);
    _primeAfterHistoryReplay();
    return changes;
  }

  WorldChangeSet redo() {
    final changes = history.redo(world);
    _primeAfterHistoryReplay();
    return changes;
  }

  void _primeAfterHistoryReplay() {
    ticks.resetAndPrime(world);
    _suppressPrimedHistory = !ticks.isIdle;
  }
}
