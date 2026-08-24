/// Persistent storage for the finite Classic world.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/widgets.dart';
import 'package:minedart_core/minedart_core.dart';
import 'package:path_provider/path_provider.dart';

/// Reads and writes `MDRT1 + int64 little-endian seed + gzip(blocks)` files.
///
/// Blocks are in the canonical chunk-list order, with each chunk retaining its
/// [ChunkIndex] storage order. The fixed byte length makes truncated and
/// otherwise incompatible saves fail closed.
final class WorldSaver {
  WorldSaver._();

  static const _magic = <int>[0x4d, 0x44, 0x52, 0x54, 0x31]; // MDRT1
  static const _headerLength = 13;
  static const _chunkCount =
      WorldDims.worldChunksX * WorldDims.worldChunksY * WorldDims.worldChunksZ;
  static const _blockCount = _chunkCount * ChunkIndex.volume;
  static const _blockBytes = _blockCount * 2;

  /// Returns `~/Library/Application Support/minedart/world.dat` on macOS.
  static Future<File> defaultFile() async {
    final applicationSupport = await getApplicationSupportDirectory();
    final directory = Directory(
      '${applicationSupport.parent.path}${Platform.pathSeparator}minedart',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}world.dat');
  }

  /// Saves a point-in-time block snapshot. Compression happens in a worker
  /// isolate; the main isolate only copies the fixed-size typed buffer.
  static Future<void> save(VoxelWorld world, File file) async {
    final rawBlocks = Uint16List(_blockCount);
    var offset = 0;
    for (final chunk in world.chunks) {
      rawBlocks.setRange(offset, offset + ChunkIndex.volume, chunk.blocks);
      offset += ChunkIndex.volume;
    }

    final compressed = await compute(
      _compressBlocks,
      TransferableTypedData.fromList([rawBlocks.buffer.asUint8List()]),
      debugLabel: 'world-save-gzip',
    );
    final compressedBytes = compressed.materialize().asUint8List();
    final output = Uint8List(_headerLength + compressedBytes.length);
    output.setRange(0, _magic.length, _magic);
    ByteData.sublistView(
      output,
    ).setInt64(_magic.length, world.seed, Endian.little);
    output.setRange(_headerLength, output.length, compressedBytes);

    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(output, flush: true);
    await temporary.rename(file.path);
  }

  /// Returns null for absent, corrupt, truncated, or incompatible save files.
  static Future<VoxelWorld?> load(File file) async {
    if (!await file.exists()) return null;

    try {
      final decoded = await compute(
        _decodeSave,
        TransferableTypedData.fromList([await file.readAsBytes()]),
        debugLabel: 'world-load-gzip',
      );
      if (decoded == null) return null;

      final rawBlocks = decoded.blocks.materialize().asUint16List();
      if (rawBlocks.length != _blockCount || !_hasValidBlockIds(rawBlocks)) {
        return null;
      }

      final world = VoxelWorld()..seed = decoded.seed;
      var offset = 0;
      for (final chunk in world.chunks) {
        chunk.blocks.setRange(0, ChunkIndex.volume, rawBlocks, offset);
        chunk.recount();
        offset += ChunkIndex.volume;
      }
      world.recomputeSkylight();
      return world;
    } on Object {
      return null;
    }
  }

  static bool _hasValidBlockIds(Uint16List blocks) {
    for (var i = 0; i < blocks.length; i++) {
      if (Blocks.id(blocks[i]) >= Blocks.count) return false;
    }
    return true;
  }
}

/// Periodic persistence plus an awaited save for a normal desktop quit.
final class WorldAutosaver {
  WorldAutosaver({required this.world, required this.file});

  static const interval = Duration(seconds: 60);

  final VoxelWorld world;
  final File file;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Future<void>? _saveTask;
  bool _saveQueued = false;

  void start() {
    _timer = Timer.periodic(interval, (_) => unawaited(saveNow()));
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await saveNow();
        return AppExitResponse.exit;
      },
    );
  }

  /// Cancels the periodic timer and lifecycle hook (final save is caller's
  /// responsibility if needed).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Coalesces periodic and exit saves while guaranteeing the exit handler
  /// waits for the newest snapshot requested before it returns.
  Future<void> saveNow() {
    _saveQueued = true;
    return _saveTask ??= _drainSaveRequests();
  }

  Future<void> _drainSaveRequests() async {
    do {
      _saveQueued = false;
      try {
        await WorldSaver.save(world, file);
      } on Object {
        // A failed autosave must not block a user-requested app exit.
      }
    } while (_saveQueued);
    _saveTask = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}

TransferableTypedData _compressBlocks(TransferableTypedData rawTransfer) {
  final raw = rawTransfer.materialize().asUint8List();
  final compressed = Uint8List.fromList(gzip.encode(raw));
  return TransferableTypedData.fromList([compressed]);
}

_DecodedSave? _decodeSave(TransferableTypedData fileTransfer) {
  final fileBytes = fileTransfer.materialize().asUint8List();
  if (fileBytes.length <= WorldSaver._headerLength) return null;
  for (var i = 0; i < WorldSaver._magic.length; i++) {
    if (fileBytes[i] != WorldSaver._magic[i]) return null;
  }

  final seed = ByteData.sublistView(
    fileBytes,
  ).getInt64(WorldSaver._magic.length, Endian.little);
  try {
    final raw = Uint8List.fromList(
      gzip.decode(Uint8List.sublistView(fileBytes, WorldSaver._headerLength)),
    );
    if (raw.length != WorldSaver._blockBytes) return null;
    return _DecodedSave(
      seed: seed,
      blocks: TransferableTypedData.fromList([raw]),
    );
  } on Object {
    return null;
  }
}

final class _DecodedSave {
  const _DecodedSave({required this.seed, required this.blocks});

  final int seed;
  final TransferableTypedData blocks;
}
