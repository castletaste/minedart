import 'package:minedart_core/minedart_core.dart';
import 'package:test/test.dart';

void main() {
  test('merge coalesces coordinates in first-seen order and unions dirty', () {
    final world = VoxelWorld();
    final firstBuilder = WorldChangeSetBuilder(world)
      ..set(16, 10, 10, Blocks.stone)
      ..set(2, 2, 2, Blocks.dirt);
    final first = firstBuilder.build();
    final secondBuilder = WorldChangeSetBuilder(world)
      ..set(2, 2, 2, Blocks.grass)
      ..set(16, 10, 10, Blocks.air)
      ..set(33, 3, 3, Blocks.sand);
    final second = secondBuilder.build();

    final merged = WorldChangeSet.merge([first, second]);

    expect(
      [for (final change in merged.changes) (change.x, change.y, change.z)],
      [(2, 2, 2), (33, 3, 3)],
    );
    expect(merged.changes.first.oldRaw, Blocks.air);
    expect(merged.changes.first.newRaw, Blocks.grass);
    expect(merged.changes.last.oldRaw, Blocks.air);
    expect(merged.changes.last.newRaw, Blocks.sand);
    expect(
      merged.dirtyChunks,
      equals({...first.dirtyChunks, ...second.dirtyChunks}),
    );
    expect(
      merged.dirtyChunks,
      contains(VoxelWorld.chunkIndexOf(1, 0, 0)),
      reason: 'dirty chunks from a coalesced no-op must be retained',
    );
  });

  test('group coalesces raw writes and undo/redo replays metadata', () {
    final world = VoxelWorld();
    final builder = WorldChangeSetBuilder(world);
    builder.set(16, 10, 10, Blocks.stone);
    builder.set(16, 10, 10, Blocks.pack(Blocks.water, 5));
    final edit = builder.build();

    expect(edit.changes, hasLength(1));
    expect(edit.changes.single.oldRaw, Blocks.air);
    expect(edit.changes.single.newRaw, Blocks.pack(Blocks.water, 5));
    expect(
      edit.dirtyChunks,
      containsAll([
        VoxelWorld.chunkIndexOf(1, 0, 0),
        VoxelWorld.chunkIndexOf(0, 0, 0),
      ]),
    );

    final history = EditHistory()..record(edit);
    final undone = history.undo(world);
    expect(world.blockAt(16, 10, 10), Blocks.air);
    expect(undone.changes.single.oldRaw, Blocks.pack(Blocks.water, 5));
    expect(undone.changes.single.newRaw, Blocks.air);
    expect(undone.dirtyChunks, contains(VoxelWorld.chunkIndexOf(0, 0, 0)));

    final redone = history.redo(world);
    expect(world.blockAt(16, 10, 10), Blocks.pack(Blocks.water, 5));
    expect(redone.changes.single.newRaw, Blocks.pack(Blocks.water, 5));
  });

  test('explicit group combines user and deterministic simulation edits', () {
    final world = VoxelWorld();
    final history = EditHistory()..beginGroup();

    final userEdit = WorldChangeSetBuilder(world)..set(4, 5, 6, Blocks.stone);
    history.record(userEdit.build());
    final simulationEdit = WorldChangeSetBuilder(world)
      ..set(4, 5, 6, Blocks.pack(Blocks.water, 3))
      ..set(4, 4, 6, Blocks.sand);
    history.record(simulationEdit.build());

    expect(history.isGroupOpen, isTrue);
    expect(history.undoLength, 0);
    history.endGroup();
    expect(history.isGroupOpen, isFalse);
    expect(history.undoLength, 1);

    history.undo(world);
    expect(world.blockAt(4, 5, 6), Blocks.air);
    expect(world.blockAt(4, 4, 6), Blocks.air);

    history.redo(world);
    expect(world.blockAt(4, 5, 6), Blocks.pack(Blocks.water, 3));
    expect(world.blockAt(4, 4, 6), Blocks.sand);
  });

  test('history caps groups and a new edit invalidates redo', () {
    final world = VoxelWorld();
    final history = EditHistory(maxGroups: 128);
    for (var i = 0; i < 130; i++) {
      history.beginGroup();
      final builder = WorldChangeSetBuilder(world)..set(i, 1, 1, Blocks.stone);
      history.record(builder.build());
      history.endGroup();
    }
    expect(history.undoLength, 128);

    history.undo(world);
    expect(history.canRedo, isTrue);
    final replacement = WorldChangeSetBuilder(world)
      ..set(200, 1, 1, Blocks.dirt);
    history.record(replacement.build());
    expect(history.canRedo, isFalse);
  });

  test('undo closes an open group before replaying it', () {
    final world = VoxelWorld();
    final history = EditHistory()..beginGroup();
    final edit = WorldChangeSetBuilder(world)..set(7, 8, 9, Blocks.logOak);
    history.record(edit.build());

    final undone = history.undo(world);

    expect(history.isGroupOpen, isFalse);
    expect(undone.isNotEmpty, isTrue);
    expect(world.blockAt(7, 8, 9), Blocks.air);
    expect(history.canRedo, isTrue);
  });

  test('redo closes an empty group and replays the prior edit', () {
    final world = VoxelWorld();
    final history = EditHistory();
    final edit = WorldChangeSetBuilder(world)..set(8, 8, 8, Blocks.glass);
    history.record(edit.build());
    history.undo(world);
    history.beginGroup();

    final redone = history.redo(world);

    expect(history.isGroupOpen, isFalse);
    expect(redone.isNotEmpty, isTrue);
    expect(world.blockAt(8, 8, 8), Blocks.glass);
  });

  test('a recorded open group invalidates redo before redo is requested', () {
    final world = VoxelWorld();
    final history = EditHistory();
    final original = WorldChangeSetBuilder(world)..set(9, 9, 9, Blocks.stone);
    history.record(original.build());
    history.undo(world);
    expect(history.canRedo, isTrue);

    history.beginGroup();
    final replacement = WorldChangeSetBuilder(world)
      ..set(10, 9, 9, Blocks.dirt);
    history.record(replacement.build());

    expect(history.canRedo, isFalse);
    expect(history.redo(world).isEmpty, isTrue);
    expect(history.isGroupOpen, isFalse);
    expect(world.blockAt(9, 9, 9), Blocks.air);
    expect(world.blockAt(10, 9, 9), Blocks.dirt);
  });

  test('clear closes and removes an open group without changing the world', () {
    final world = VoxelWorld();
    final history = EditHistory()..beginGroup();
    final edit = WorldChangeSetBuilder(world)..set(11, 9, 9, Blocks.brick);
    history.record(edit.build());

    history.clear();

    expect(history.isGroupOpen, isFalse);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    expect(world.blockAt(11, 9, 9), Blocks.brick);
  });

  test('starting a group safely commits a previously open group', () {
    final world = VoxelWorld();
    final history = EditHistory(maxGroups: 2)..beginGroup();
    final first = WorldChangeSetBuilder(world)..set(12, 9, 9, Blocks.stone);
    history.record(first.build());

    history.beginGroup();
    expect(history.undoLength, 1);
    final second = WorldChangeSetBuilder(world)..set(13, 9, 9, Blocks.dirt);
    history.record(second.build());
    history.endGroup();

    history.beginGroup();
    final third = WorldChangeSetBuilder(world)..set(14, 9, 9, Blocks.sand);
    history.record(third.build());
    history.endGroup();
    expect(history.undoLength, 2);

    history.undo(world);
    history.undo(world);
    expect(world.blockAt(12, 9, 9), Blocks.stone);
    expect(world.blockAt(13, 9, 9), Blocks.air);
    expect(world.blockAt(14, 9, 9), Blocks.air);
  });

  test('net-zero writes produce no history group', () {
    final world = VoxelWorld();
    final builder = WorldChangeSetBuilder(world);
    builder.set(2, 2, 2, Blocks.stone);
    builder.set(2, 2, 2, Blocks.air);
    final changes = builder.build();

    expect(changes.isEmpty, isTrue);
    expect(world.blockAt(2, 2, 2), Blocks.air);
  });
}
