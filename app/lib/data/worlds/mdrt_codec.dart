/// MDRT1/MDRT2 binary serialization. This library is Flutter-free.
library;

import 'dart:convert';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:minedart_core/src/block.dart';

import 'gzip_codec.dart';
import 'world_models.dart';

final class MdrtCodec {
  MdrtCodec._();

  static const int currentFormatVersion = 2;
  static const _mdrt1Magic = <int>[0x4d, 0x44, 0x52, 0x54, 0x31];
  static const _mdrt2Magic = <int>[0x4d, 0x44, 0x52, 0x54, 0x32];
  static const _mdrt1HeaderLength = 13;
  static const _mdrt2HeaderLength = 9;
  static const _blockByteLength = WorldDocument.blockCount * 2;

  static Future<Uint8List> encode(WorldDocument document) async {
    _validateMetadataId(document.metadata.id);
    final blocks = document.unmodifiableBlocks;
    _validateBlocks(blocks);
    final metadata = document.metadata.copyWith(
      formatVersion: currentFormatVersion,
    );
    final jsonBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(metadata.toJson())),
    );
    final raw = Uint8List.sublistView(blocks);
    final compressed = await gzipEncode(raw);
    final output = Uint8List(
      _mdrt2HeaderLength + jsonBytes.length + compressed.length,
    );
    output.setRange(0, _mdrt2Magic.length, _mdrt2Magic);
    final data = ByteData.sublistView(output);
    data.setUint32(_mdrt2Magic.length, jsonBytes.length, Endian.little);
    output.setRange(
      _mdrt2HeaderLength,
      _mdrt2HeaderLength + jsonBytes.length,
      jsonBytes,
    );
    output.setRange(
      _mdrt2HeaderLength + jsonBytes.length,
      output.length,
      compressed,
    );
    return output;
  }

  /// Decodes MDRT2, or migrates a legacy MDRT1 byte stream in memory.
  static Future<WorldDocument> decode(
    Uint8List bytes, {
    WorldMetadata? legacyMetadata,
  }) async {
    if (_hasMagic(bytes, _mdrt2Magic)) return _decodeV2(bytes);
    if (_hasMagic(bytes, _mdrt1Magic)) return _decodeV1(bytes, legacyMetadata);
    throw const FormatException('Unknown Minedart world format');
  }

  static Future<WorldDocument> _decodeV2(Uint8List bytes) async {
    if (bytes.length < _mdrt2HeaderLength) {
      throw const FormatException('Truncated MDRT2 header');
    }
    final metadataLength = ByteData.sublistView(
      bytes,
    ).getUint32(_mdrt2Magic.length, Endian.little);
    final payloadOffset = _mdrt2HeaderLength + metadataLength;
    if (metadataLength == 0 || payloadOffset >= bytes.length) {
      throw const FormatException('Invalid MDRT2 sections');
    }
    final dynamic decodedJson;
    try {
      decodedJson = jsonDecode(
        utf8.decode(
          Uint8List.sublistView(bytes, _mdrt2HeaderLength, payloadOffset),
        ),
      );
    } on Object {
      throw const FormatException('Invalid MDRT2 metadata JSON');
    }
    if (decodedJson is! Map) {
      throw const FormatException('Invalid MDRT2 metadata');
    }
    final metadata = WorldMetadata.fromJson(
      Map<String, Object?>.from(decodedJson),
    );
    if (metadata.formatVersion != currentFormatVersion) {
      throw FormatException(
        'Unsupported MDRT2 format ${metadata.formatVersion}',
      );
    }
    final raw = await _decodeBlocks(
      Uint8List.sublistView(bytes, payloadOffset),
    );
    return WorldDocument(metadata: metadata, blocks: raw);
  }

  /// Reads MDRT2 library metadata without inflating the 8 MiB block payload.
  /// Legacy MDRT1 has no metadata section and returns null for full fallback.
  static WorldMetadata? decodeMetadata(Uint8List bytes) {
    if (!_hasMagic(bytes, _mdrt2Magic)) return null;
    if (bytes.length < _mdrt2HeaderLength) {
      throw const FormatException('Truncated MDRT2 header');
    }
    final metadataLength = ByteData.sublistView(
      bytes,
    ).getUint32(_mdrt2Magic.length, Endian.little);
    final payloadOffset = _mdrt2HeaderLength + metadataLength;
    if (metadataLength == 0 || payloadOffset >= bytes.length) {
      throw const FormatException('Invalid MDRT2 sections');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(
          Uint8List.sublistView(bytes, _mdrt2HeaderLength, payloadOffset),
        ),
      );
    } on Object {
      throw const FormatException('Invalid MDRT2 metadata JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('Invalid MDRT2 metadata');
    }
    final metadata = WorldMetadata.fromJson(Map<String, Object?>.from(decoded));
    if (metadata.formatVersion != currentFormatVersion) {
      throw FormatException(
        'Unsupported MDRT2 format ${metadata.formatVersion}',
      );
    }
    return metadata;
  }

  static Future<WorldDocument> _decodeV1(
    Uint8List bytes,
    WorldMetadata? legacyMetadata,
  ) async {
    if (bytes.length <= _mdrt1HeaderLength) {
      throw const FormatException('Truncated MDRT1');
    }
    final seed = ByteData.sublistView(
      bytes,
    ).getInt64(_mdrt1Magic.length, Endian.little);
    final raw = await _decodeBlocks(
      Uint8List.sublistView(bytes, _mdrt1HeaderLength),
    );
    final now = DateTime.now().toUtc();
    final source =
        legacyMetadata ??
        WorldMetadata(
          id: 'legacy-$seed',
          name: 'Imported Classic World',
          seed: seed,
          createdAt: now,
          updatedAt: now,
          spawn: const WorldSpawn.origin(),
        );
    _validateMetadataId(source.id);
    return WorldDocument(
      metadata: source.copyWith(
        seed: seed,
        formatVersion: currentFormatVersion,
      ),
      blocks: raw,
    );
  }

  static Future<Uint16List> _decodeBlocks(Uint8List compressed) async {
    final raw = await gzipDecode(compressed, maxOutputBytes: _blockByteLength);
    if (raw.length != _blockByteLength) {
      throw const FormatException('Unexpected world block payload length');
    }
    final blocks = Uint16List.view(raw.buffer, raw.offsetInBytes);
    _validateBlocks(blocks);
    return blocks;
  }

  static void _validateBlocks(Uint16List blocks) {
    if (blocks.length != WorldDocument.blockCount) {
      throw const FormatException('Unexpected world block count');
    }
    for (final raw in blocks) {
      // The core owns the current definitions. Legacy ids 1..21 are included.
      if ((raw & 0x0fff) >= Blocks.count) {
        throw const FormatException('World contains unsupported block id');
      }
    }
  }

  static void _validateMetadataId(String id) {
    if (!isSafeWorldId(id)) {
      throw const FormatException('World metadata id is unsafe');
    }
  }

  static bool _hasMagic(Uint8List bytes, List<int> magic) =>
      bytes.length >= magic.length &&
      List<bool>.generate(
        magic.length,
        (i) => bytes[i] == magic[i],
      ).every((v) => v);
}
