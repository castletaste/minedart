/// Repository contract shared by native files and web IndexedDB.
library;

import 'dart:typed_data';

import 'world_models.dart';

abstract interface class WorldRepository {
  Future<List<WorldSummary>> list();
  Future<WorldDocument> create(WorldDocument document);
  Future<WorldDocument?> load(String id);
  Future<void> save(WorldDocument document);
  Future<WorldSummary?> rename(String id, String name);
  Future<WorldDocument?> duplicate(String id, WorldMetadata metadata);
  Future<bool> delete(String id);
  Future<WorldDocument> importBytes(
    Uint8List bytes, {
    WorldMetadata? legacyMetadata,
  });
  Future<Uint8List> exportBytes(String id);
}

final class WorldNotFoundException implements Exception {
  const WorldNotFoundException(this.id);
  final String id;

  @override
  String toString() => 'WorldNotFoundException($id)';
}
