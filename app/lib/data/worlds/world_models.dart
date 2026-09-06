/// Immutable domain objects used by world persistence.
library;

import 'dart:typed_data';

// ignore: implementation_imports
import 'package:minedart_core/src/chunk.dart';
// ignore: implementation_imports
import 'package:minedart_core/src/world.dart';

/// Player location and view direction saved with a world.
final class WorldSpawn {
  const WorldSpawn({
    required this.x,
    required this.y,
    required this.z,
    this.yaw = 0,
    this.pitch = 0,
  });

  const WorldSpawn.origin() : this(x: 0, y: 0, z: 0);

  final double x;
  final double y;
  final double z;
  final double yaw;
  final double pitch;

  Map<String, Object> toJson() => <String, Object>{
    'x': x,
    'y': y,
    'z': z,
    'yaw': yaw,
    'pitch': pitch,
  };

  factory WorldSpawn.fromJson(Map<String, Object?> json) => WorldSpawn(
    x: _number(json['x'], 'spawn.x'),
    y: _number(json['y'], 'spawn.y'),
    z: _number(json['z'], 'spawn.z'),
    yaw: _numberOr(json['yaw'], 0, 'spawn.yaw'),
    pitch: _numberOr(json['pitch'], 0, 'spawn.pitch'),
  );

  @override
  bool operator ==(Object other) =>
      other is WorldSpawn &&
      x == other.x &&
      y == other.y &&
      z == other.z &&
      yaw == other.yaw &&
      pitch == other.pitch;

  @override
  int get hashCode => Object.hash(x, y, z, yaw, pitch);
}

/// Metadata carried by MDRT2 independently of the block payload.
final class WorldMetadata {
  const WorldMetadata({
    required this.id,
    required this.name,
    required this.seed,
    required this.createdAt,
    required this.updatedAt,
    required this.spawn,
    this.formatVersion = 2,
  });

  final String id;
  final String name;
  final int seed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final WorldSpawn spawn;
  final int formatVersion;

  WorldMetadata copyWith({
    String? id,
    String? name,
    int? seed,
    DateTime? createdAt,
    DateTime? updatedAt,
    WorldSpawn? spawn,
    int? formatVersion,
  }) => WorldMetadata(
    id: id ?? this.id,
    name: name ?? this.name,
    seed: seed ?? this.seed,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    spawn: spawn ?? this.spawn,
    formatVersion: formatVersion ?? this.formatVersion,
  );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'seed': seed,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'spawn': spawn.toJson(),
    'formatVersion': formatVersion,
  };

  factory WorldMetadata.fromJson(Map<String, Object?> json) {
    final spawn = json['spawn'];
    if (spawn is! Map) throw const FormatException('MDRT2 spawn is invalid');
    final id = _string(json['id'], 'id');
    if (!isSafeWorldId(id)) {
      throw const FormatException('MDRT2 id is unsafe');
    }
    return WorldMetadata(
      id: id,
      name: _string(json['name'], 'name'),
      seed: _integer(json['seed'], 'seed'),
      createdAt: _date(json['createdAt'], 'createdAt'),
      updatedAt: _date(json['updatedAt'], 'updatedAt'),
      spawn: WorldSpawn.fromJson(Map<String, Object?>.from(spawn)),
      formatVersion: _integer(json['formatVersion'], 'formatVersion'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorldMetadata &&
      id == other.id &&
      name == other.name &&
      seed == other.seed &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt &&
      spawn == other.spawn &&
      formatVersion == other.formatVersion;

  @override
  int get hashCode =>
      Object.hash(id, name, seed, createdAt, updatedAt, spawn, formatVersion);
}

bool isSafeWorldId(String id) =>
    id.isNotEmpty &&
    id.length <= 64 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

/// Lightweight world-library entry.
final class WorldSummary {
  const WorldSummary(this.metadata);

  final WorldMetadata metadata;

  String get id => metadata.id;
  String get name => metadata.name;
  int get seed => metadata.seed;
  DateTime get updatedAt => metadata.updatedAt;
}

/// Immutable canonical world payload. [blocks] always returns a defensive copy.
final class WorldDocument {
  WorldDocument({required this.metadata, required Uint16List blocks})
    : _blocks = Uint16List.fromList(blocks) {
    if (_blocks.length != blockCount) {
      throw ArgumentError.value(
        blocks.length,
        'blocks',
        'Unexpected block count',
      );
    }
  }

  WorldDocument._({required this.metadata, required Uint16List ownedBlocks})
    : _blocks = ownedBlocks;

  factory WorldDocument.fromWorld({
    required WorldMetadata metadata,
    required VoxelWorld world,
  }) {
    final blocks = Uint16List(blockCount);
    var offset = 0;
    for (final chunk in world.chunks) {
      blocks.setRange(offset, offset + ChunkIndex.volume, chunk.blocks);
      offset += ChunkIndex.volume;
    }
    return WorldDocument._(metadata: metadata, ownedBlocks: blocks);
  }

  static const int chunkCount =
      WorldDims.worldChunksX * WorldDims.worldChunksY * WorldDims.worldChunksZ;
  static const int blockCount = chunkCount * ChunkIndex.volume;

  final WorldMetadata metadata;
  final Uint16List _blocks;

  Uint16List get blocks => Uint16List.fromList(_blocks);

  /// Zero-copy read access for serializers. The returned typed-data view
  /// rejects every mutation and never exposes the mutable backing list.
  Uint16List get unmodifiableBlocks => _blocks.asUnmodifiableView();

  /// Materializes a fresh mutable core world for the game runtime.
  VoxelWorld toVoxelWorld() {
    final world = VoxelWorld()..seed = metadata.seed;
    var offset = 0;
    for (final chunk in world.chunks) {
      chunk.blocks.setRange(0, ChunkIndex.volume, _blocks, offset);
      chunk.recount();
      offset += ChunkIndex.volume;
    }
    world.recomputeSkylight();
    return world;
  }

  WorldDocument copyWith({WorldMetadata? metadata, Uint16List? blocks}) {
    if (blocks != null) {
      return WorldDocument(metadata: metadata ?? this.metadata, blocks: blocks);
    }
    return WorldDocument._(
      metadata: metadata ?? this.metadata,
      ownedBlocks: _blocks,
    );
  }
}

String _string(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('MDRT2 $field is invalid');
}

int _integer(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('MDRT2 $field is invalid');
}

double _number(Object? value, String field) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('MDRT2 $field is invalid');
}

double _numberOr(Object? value, double fallback, String field) {
  if (value == null) return fallback;
  return _number(value, field);
}

DateTime _date(Object? value, String field) {
  if (value is! String) throw FormatException('MDRT2 $field is invalid');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('MDRT2 $field is invalid');
  return parsed.toUtc();
}
