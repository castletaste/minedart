library;

import 'dart:typed_data';

import 'mdrt_codec.dart';
import 'world_models.dart';
import 'world_repository.dart';

/// Storage seam shared by file and IndexedDB implementations.
abstract interface class WorldByteStore {
  Future<List<String>> keys();
  Future<Uint8List?> read(String id);
  Future<void> write(String id, Uint8List bytes);
  Future<bool> remove(String id);
}

/// Implements domain operations over an atomic byte store; useful for fakes too.
class StoredWorldRepository implements WorldRepository {
  StoredWorldRepository(this.store, {DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final WorldByteStore store;
  final DateTime Function() _clock;

  @override
  Future<List<WorldSummary>> list() async {
    final summaries = <WorldSummary>[];
    for (final id in await store.keys()) {
      final bytes = await store.read(id);
      if (bytes == null) continue;
      try {
        final metadata =
            MdrtCodec.decodeMetadata(bytes) ??
            (await MdrtCodec.decode(bytes)).metadata;
        if (metadata.id == id) {
          summaries.add(WorldSummary(metadata));
        }
      } on Object {
        // A corrupt isolated file/record must not hide the rest of the library.
      }
    }
    summaries.sort((a, b) {
      final updated = b.updatedAt.compareTo(a.updatedAt);
      return updated != 0 ? updated : a.id.compareTo(b.id);
    });
    return List<WorldSummary>.unmodifiable(summaries);
  }

  @override
  Future<WorldDocument> create(WorldDocument document) async {
    _checkId(document.metadata.id);
    if (await store.read(document.metadata.id) != null) {
      throw StateError('World already exists: ${document.metadata.id}');
    }
    await save(document);
    return document;
  }

  @override
  Future<WorldDocument?> load(String id) async {
    _checkId(id);
    final bytes = await store.read(id);
    if (bytes == null) return null;
    final document = await MdrtCodec.decode(bytes);
    if (document.metadata.id != id) {
      throw const FormatException(
        'World storage key does not match metadata id',
      );
    }
    return document;
  }

  @override
  Future<void> save(WorldDocument document) async {
    _checkId(document.metadata.id);
    await store.write(document.metadata.id, await MdrtCodec.encode(document));
  }

  @override
  Future<WorldSummary?> rename(String id, String name) async {
    _checkId(id);
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final source = await load(id);
    if (source == null) return null;
    final renamed = source.copyWith(
      metadata: source.metadata.copyWith(name: normalized, updatedAt: _clock()),
    );
    await save(renamed);
    return WorldSummary(renamed.metadata);
  }

  @override
  Future<WorldDocument?> duplicate(String id, WorldMetadata metadata) async {
    _checkId(id);
    _checkId(metadata.id);
    final source = await load(id);
    if (source == null) return null;
    if (metadata.id == id || await store.read(metadata.id) != null) {
      throw StateError('Duplicate world id already exists: ${metadata.id}');
    }
    final duplicate = source.copyWith(
      metadata: metadata.copyWith(seed: source.metadata.seed, formatVersion: 2),
    );
    await save(duplicate);
    return duplicate;
  }

  @override
  Future<bool> delete(String id) async {
    _checkId(id);
    if (await store.read(id) == null) return false;
    return store.remove(id);
  }

  @override
  Future<WorldDocument> importBytes(
    Uint8List bytes, {
    WorldMetadata? legacyMetadata,
  }) async {
    var document = await MdrtCodec.decode(
      bytes,
      legacyMetadata: legacyMetadata,
    );
    _checkId(document.metadata.id);
    if (await store.read(document.metadata.id) != null) {
      final base = document.metadata.id.length > 40
          ? document.metadata.id.substring(0, 40)
          : document.metadata.id;
      var suffix = _clock().microsecondsSinceEpoch.toRadixString(36);
      var candidate = '$base-copy-$suffix';
      var attempt = 2;
      while (await store.read(candidate) != null) {
        candidate = '$base-copy-$suffix-${attempt++}';
      }
      document = document.copyWith(
        metadata: document.metadata.copyWith(
          id: candidate,
          createdAt: _clock(),
          updatedAt: _clock(),
        ),
      );
    }
    await save(document);
    return document;
  }

  @override
  Future<Uint8List> exportBytes(String id) async {
    _checkId(id);
    final document = await load(id);
    if (document == null) throw WorldNotFoundException(id);
    return MdrtCodec.encode(document);
  }
}

void _checkId(String id) {
  if (!isSafeWorldId(id)) {
    throw ArgumentError.value(id, 'id', 'must be a safe world identifier');
  }
}

/// Deterministic fake adapter for unit tests without a browser or file system.
final class MemoryWorldByteStore implements WorldByteStore {
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};

  @override
  Future<List<String>> keys() async => List<String>.unmodifiable(_bytes.keys);

  @override
  Future<Uint8List?> read(String id) async {
    final bytes = _bytes[id];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    _bytes[id] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> remove(String id) async => _bytes.remove(id) != null;
}
