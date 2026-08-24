library;

import '../world.dart';
import 'world_change.dart';

/// Capped grouped undo/redo history. Recording a new edit invalidates redo.
final class EditHistory {
  EditHistory({this.maxGroups = 128}) : assert(maxGroups > 0);

  final int maxGroups;
  final List<WorldChangeSet> _undo = [];
  final List<WorldChangeSet> _redo = [];
  List<WorldChangeSet>? _openGroup;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isGroupOpen => _openGroup != null;
  int get undoLength => _undo.length;
  int get redoLength => _redo.length;

  /// Starts an explicit undo group.
  ///
  /// Starting another group first closes and commits the current one. Calls to
  /// [record] remain immediate, single-change-set groups when no group is open.
  void beginGroup() {
    endGroup();
    _openGroup = [];
  }

  /// Closes the current group and records its coalesced net change.
  ///
  /// Empty and net-zero groups do not consume history. Recording any non-empty
  /// change set still invalidates redo immediately, as a normal new edit does.
  void endGroup() {
    final group = _openGroup;
    if (group == null) return;
    _openGroup = null;
    _commit(WorldChangeSet.merge(group));
  }

  void record(WorldChangeSet changes) {
    if (changes.isEmpty) return;
    final group = _openGroup;
    if (group != null) {
      group.add(changes);
      _redo.clear();
      return;
    }
    _commit(changes);
  }

  WorldChangeSet undo(VoxelWorld world) {
    endGroup();
    if (_undo.isEmpty) return WorldChangeSet.empty();
    final original = _undo.removeLast();
    final applied = original.inverted.applyTo(world);
    _redo.add(original);
    return applied;
  }

  WorldChangeSet redo(VoxelWorld world) {
    endGroup();
    if (_redo.isEmpty) return WorldChangeSet.empty();
    final original = _redo.removeLast();
    final applied = original.applyTo(world);
    _undo.add(original);
    if (_undo.length > maxGroups) _undo.removeAt(0);
    return applied;
  }

  void clear() {
    endGroup();
    _undo.clear();
    _redo.clear();
  }

  void _commit(WorldChangeSet changes) {
    if (changes.isEmpty) return;
    _undo.add(changes);
    if (_undo.length > maxGroups) _undo.removeAt(0);
    _redo.clear();
  }
}
