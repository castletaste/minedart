import 'dart:collection';

import 'package:flutter/foundation.dart';

@immutable
final class WorldLibraryEntry {
  const WorldLibraryEntry({
    required this.id,
    required this.name,
    required this.seed,
    required this.updatedAt,
    this.formatVersion = 2,
    this.isCurrent = false,
  });

  final String id;
  final String name;
  final int seed;
  final DateTime updatedAt;
  final int formatVersion;
  final bool isCurrent;

  WorldLibraryEntry copyWith({
    String? name,
    int? seed,
    DateTime? updatedAt,
    int? formatVersion,
    bool? isCurrent,
  }) => WorldLibraryEntry(
    id: id,
    name: name ?? this.name,
    seed: seed ?? this.seed,
    updatedAt: updatedAt ?? this.updatedAt,
    formatVersion: formatVersion ?? this.formatVersion,
    isCurrent: isCurrent ?? this.isCurrent,
  );
}

enum WorldLibraryAction {
  load('Load'),
  rename('Rename'),
  duplicate('Duplicate'),
  delete('Delete'),
  reset('Reset'),
  exportWorld('Export'),
  shareSeed('Share seed');

  const WorldLibraryAction(this.label);

  final String label;

  bool get isDestructive =>
      this == WorldLibraryAction.delete || this == WorldLibraryAction.reset;
}

/// A terrain choice owned by the World Library UI.
///
/// It deliberately has no persistence or world-generation knowledge. The
/// integration layer maps this choice to its launch/world-generation preset.
enum WorldLibraryPreset {
  classic('Classic', 'Hills, caves and forests'),
  flat('Flat', 'Open ground for building'),
  islands('Islands', 'Ocean archipelagos');

  const WorldLibraryPreset(this.label, this.description);

  final String label;
  final String description;
}

typedef CreateWorldCallback =
    Future<void> Function(String name, int? seed, WorldLibraryPreset preset);
typedef WorldEntryCallback = Future<void> Function(WorldLibraryEntry world);
typedef RenameWorldCallback =
    Future<void> Function(WorldLibraryEntry world, String newName);

/// External operations supplied by the integration layer.
///
/// The UI does not know whether a repository uses native files or IndexedDB,
/// nor how [WorldLibraryPreset] maps to a generated world.
@immutable
final class WorldLibraryCallbacks {
  const WorldLibraryCallbacks({
    required this.onCreate,
    required this.onImport,
    required this.onLoad,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
    required this.onReset,
    required this.onExport,
    required this.onShareSeed,
  });

  final CreateWorldCallback onCreate;
  final Future<void> Function() onImport;
  final WorldEntryCallback onLoad;
  final RenameWorldCallback onRename;
  final WorldEntryCallback onDuplicate;
  final WorldEntryCallback onDelete;
  final WorldEntryCallback onReset;
  final WorldEntryCallback onExport;
  final WorldEntryCallback onShareSeed;
}

final class WorldLibraryController extends ChangeNotifier {
  WorldLibraryController({Iterable<WorldLibraryEntry> worlds = const []})
    : _worlds = List<WorldLibraryEntry>.of(worlds);

  final List<WorldLibraryEntry> _worlds;
  String _query = '';
  String? _busyWorldId;
  String? _errorMessage;

  UnmodifiableListView<WorldLibraryEntry> get worlds =>
      UnmodifiableListView<WorldLibraryEntry>(_worlds);

  String get query => _query;
  String? get busyWorldId => _busyWorldId;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _busyWorldId != null;

  List<WorldLibraryEntry> get visibleWorlds {
    final normalized = _query.trim().toLowerCase();
    final result = _worlds.where((world) {
      if (normalized.isEmpty) return true;
      return world.name.toLowerCase().contains(normalized) ||
          world.seed.toString().contains(normalized);
    }).toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  void replaceWorlds(Iterable<WorldLibraryEntry> worlds) {
    _worlds
      ..clear()
      ..addAll(worlds);
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> run(String worldId, Future<void> Function() operation) async {
    if (_busyWorldId != null) return;
    _busyWorldId = worldId;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } on Object catch (error) {
      _errorMessage = error.toString();
    } finally {
      _busyWorldId = null;
      notifyListeners();
    }
  }
}
