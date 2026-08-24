import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:minedart_core/minedart_core.dart';

/// Compatibility metadata retained on catalog entries.
enum BlockCategory {
  all('All'),
  terrain('Terrain'),
  construction('Construction'),
  nature('Nature'),
  ores('Ores'),
  utility('Utility');

  const BlockCategory(this.label);

  final String label;
}

/// UI-safe projection of one canonical core [BlockDef].
@immutable
final class BlockCatalogEntry {
  const BlockCatalogEntry({
    required this.id,
    required this.name,
    required this.category,
  });

  final int id;
  final String name;
  final BlockCategory category;

  String get semanticsLabel => 'Block $name, ID $id';
}

/// Catalog and replacement-slot state for the compact block inventory.
///
/// The catalog is projected from [blockDefs] instead of duplicating the block
/// registry. [visibleBlocks] contains only blocks that are not already present
/// in the nine-slot hotbar.
final class BuilderStudioController extends ChangeNotifier {
  BuilderStudioController({List<int>? initialHotbar, int hotbarSlotCount = 9})
    : assert(hotbarSlotCount > 0),
      _catalog = _readCatalog(),
      _hotbar = _initialHotbar(_readCatalog(), initialHotbar, hotbarSlotCount) {
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
      entries.add(
        BlockCatalogEntry(
          id: id,
          name: displayName,
          category: _categoryFor(definition),
        ),
      );
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
      'stone',
      'dirt',
      'grass',
      'planks oak',
      'cobblestone',
      'sand',
      'log oak',
      'leaves oak',
      'tnt',
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

  static BlockCategory _categoryFor(BlockDef definition) {
    final name = definition.name;
    if (name.startsWith('ore_') ||
        name == 'gold_block' ||
        name == 'iron_block' ||
        name == 'block_gold' ||
        name == 'block_iron') {
      return BlockCategory.ores;
    }
    switch (definition.behavior) {
      case BlockBehavior.falling:
        return BlockCategory.terrain;
      case BlockBehavior.water ||
          BlockBehavior.lava ||
          BlockBehavior.sponge ||
          BlockBehavior.tnt:
        return BlockCategory.utility;
      case BlockBehavior.plant:
        return BlockCategory.nature;
      case BlockBehavior.plain:
        break;
    }
    if (definition.cross ||
        name.contains('log') ||
        name.contains('leaves') ||
        name.contains('sapling') ||
        name.contains('flower') ||
        name.contains('mushroom')) {
      return BlockCategory.nature;
    }
    if (name == 'stone' ||
        name == 'dirt' ||
        name == 'grass' ||
        name == 'sand' ||
        name == 'gravel' ||
        name == 'bedrock') {
      return BlockCategory.terrain;
    }
    return BlockCategory.construction;
  }
}
