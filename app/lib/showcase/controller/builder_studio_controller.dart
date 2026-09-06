import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:minedart_core/minedart_core.dart';

/// UI-safe projection of one canonical core [BlockDef].
@immutable
final class BlockCatalogEntry {
  const BlockCatalogEntry({required this.id, required this.name});

  final int id;
  final String name;

  String get semanticsLabel => 'Block $name, ID $id';
}

/// Catalog and authoritative session hotbar state for the compact inventory.
///
/// The catalog is projected from [blockDefs] instead of duplicating the block
/// registry. Integration mirrors this hotbar into each active game runtime;
/// [visibleBlocks] contains only blocks that are not already assigned.
final class BuilderStudioController extends ChangeNotifier {
  factory BuilderStudioController({
    List<int>? initialHotbar,
    int hotbarSlotCount = 9,
  }) {
    assert(hotbarSlotCount > 0);
    final catalog = _readCatalog();
    return BuilderStudioController._(
      catalog,
      _initialHotbar(catalog, initialHotbar, hotbarSlotCount),
    );
  }

  BuilderStudioController._(this._catalog, this._hotbar) {
    _selectedBlockId = visibleBlocks.firstOrNull?.id;
  }

  final List<BlockCatalogEntry> _catalog;
  final List<int> _hotbar;
  int? _selectedBlockId;
  int _selectedHotbarSlot = 0;

  UnmodifiableListView<BlockCatalogEntry> get catalog =>
      UnmodifiableListView<BlockCatalogEntry>(_catalog);

  UnmodifiableListView<int> get hotbar => UnmodifiableListView<int>(_hotbar);

  int? get selectedBlockId => _selectedBlockId;
  int get selectedHotbarSlot => _selectedHotbarSlot;

  BlockCatalogEntry? get selectedBlock {
    final id = _selectedBlockId;
    if (id == null) return null;
    return _entryFor(id);
  }

  List<BlockCatalogEntry> get visibleBlocks {
    final assigned = _hotbar.toSet();
    return _catalog
        .where((entry) => !assigned.contains(entry.id))
        .toList(growable: false);
  }

  void selectBlock(int blockId) {
    if (_selectedBlockId == blockId || _entryFor(blockId) == null) return;
    _selectedBlockId = blockId;
    notifyListeners();
  }

  void selectHotbarSlot(int slot) {
    if (slot < 0 || slot >= _hotbar.length || slot == _selectedHotbarSlot) {
      return;
    }
    _selectedHotbarSlot = slot;
    notifyListeners();
  }

  void assignSelectedToHotbar() {
    final blockId = _selectedBlockId;
    if (blockId == null) return;
    assignBlockToHotbar(blockId, _selectedHotbarSlot);
  }

  void assignBlockToHotbar(int blockId, int slot) {
    if (_entryFor(blockId) == null || slot < 0 || slot >= _hotbar.length) {
      return;
    }
    final changed = _hotbar[slot] != blockId || _selectedHotbarSlot != slot;
    _hotbar[slot] = blockId;
    _selectedHotbarSlot = slot;
    _selectedBlockId = blockId;
    if (changed) notifyListeners();
  }

  BlockCatalogEntry? entryFor(int blockId) => _entryFor(blockId);

  BlockCatalogEntry? _entryFor(int blockId) {
    for (final entry in _catalog) {
      if (entry.id == blockId) return entry;
    }
    return null;
  }

  static List<BlockCatalogEntry> _readCatalog() {
    final entries = <BlockCatalogEntry>[];
    for (var id = 1; id < blockDefs.length; id++) {
      final definition = blockDefs[id];
      if (definition == null) continue;
      final displayName = definition.name.replaceAll('_', ' ');
      entries.add(BlockCatalogEntry(id: id, name: displayName));
    }
    return List<BlockCatalogEntry>.unmodifiable(entries);
  }

  static List<int> _initialHotbar(
    List<BlockCatalogEntry> catalog,
    List<int>? requested,
    int slotCount,
  ) {
    if (catalog.isEmpty) return List<int>.filled(slotCount, Blocks.air);
    final validIds = catalog.map((entry) => entry.id).toSet();
    const preferredNames = <String>[
      'tnt',
      'stone',
      'dirt',
      'grass',
      'planks oak',
      'cobblestone',
      'sand',
      'log oak',
      'leaves oak',
    ];
    final preferred = <int>[
      for (final name in preferredNames)
        ...catalog
            .where((entry) => entry.name == name)
            .map((entry) => entry.id),
    ];
    final result = <int>[
      ...?requested?.where(validIds.contains),
    ].take(slotCount).toList();
    for (final blockId in <int>[
      ...preferred,
      ...catalog.map((entry) => entry.id),
    ]) {
      if (result.length == slotCount) break;
      if (!result.contains(blockId)) result.add(blockId);
    }
    while (result.length < slotCount) {
      result.add(catalog[result.length % catalog.length].id);
    }
    return List<int>.of(result, growable: false);
  }
}
