import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart';

const _atlasSize = 256;
const _tileSize = 16;
const _firstUnusedTile = 37;
const _sourceWidth = 1254;
const _sourceHeight = 1254;
const _sourceSha256 =
    '390534263eca3f5becc510146361402f085ecdb65acad94617e77b7ad13c7c02';
const _legacyGeneratorSha256 =
    '3d254dd2905016b980b8005781de6319ce9cfacac648dd1bc8d7d05622db60fc';
const _legacyAtlasSha256 =
    'af0edc90fd8bdd8c587fdbb828da5fe110fb583557c0555429db9ab317fd776f';
const _preObsidianLegacyGeneratorSha256 =
    'd685041766bb869f336028575037778bbd8fd75a04cccf893b74f6d3fa7d4134';
const _preObsidianLegacyAtlasSha256 =
    '5bed18299c2bb9eb14c6e8caedf9c261ff43bb402484f4d65c0ba2c1f4c624ad';
const _preObsidianAlphaAtlasSha256 =
    'a0d4fdb791319ad28d729e79e1a70ff20b92c9e4b1ed4664b60250b43a7b917d';
const _generationId = '01a0353c-e237-78a2-84fc-bdb50d206ba7';
const _artifactId = 'exec-ef38e19a-00ec-4fad-80a3-9ddc5258e2c5';
const _originalSourcePath =
    '/Users/savva/.codex/generated_images/$_generationId/$_artifactId.png';
const _sourceRoot = 'tool/atlas_sources/default_alpha';
const _referencePath = '$_sourceRoot/reference/accepted-sheet.png';
const _mastersPath = '$_sourceRoot/masters';
const _provenancePath = '$_sourceRoot/atlas.provenance.json';
const _outputPath = 'assets/textures/atlas_alpha.png';

const _tileNames = <String>[
  'stone',
  'dirt',
  'grass-top',
  'grass-side',
  'sand',
  'gravel',
  'log-side',
  'log-top',
  'leaves',
  'water',
  'bedrock',
  'ore-coal',
  'ore-iron',
  'ore-gold',
  'planks',
  'cobblestone',
  'glass',
  'brick',
  'sponge',
  'flower-dandelion',
  'flower-rose',
  'mushroom-brown',
  'mushroom-red',
  'lava',
  'tnt-side',
  'tnt-top',
  'tnt-bottom',
  'sapling',
  'gold-block',
  'iron-block',
  'cloth-white',
  'cloth-red',
  'cloth-orange',
  'cloth-yellow',
  'cloth-lime',
  'cloth-blue',
  'obsidian',
];

const _columns = <_AxisSpan>[
  _AxisSpan(20, 293),
  _AxisSpan(329, 292),
  _AxisSpan(638, 292),
  _AxisSpan(947, 289),
];

const _rows = <_AxisSpan>[
  _AxisSpan(19, 295),
  _AxisSpan(332, 278),
  _AxisSpan(629, 291),
  _AxisSpan(937, 297),
];

const _acceptedCells = <String, _AcceptedCell>{
  'r0c0': _AcceptedCell(2, 'grass-top'),
  'r0c1': _AcceptedCell(3, 'grass-side'),
  'r0c2': _AcceptedCell(1, 'dirt'),
  'r0c3': _AcceptedCell(0, 'stone'),
  'r1c0': _AcceptedCell(4, 'sand'),
  'r1c1': _AcceptedCell(5, 'gravel'),
  'r1c2': _AcceptedCell(6, 'log-side'),
  'r1c3': _AcceptedCell(7, 'log-top'),
  'r2c0': _AcceptedCell(8, 'leaves'),
  'r2c1': _AcceptedCell(9, 'water'),
  'r2c2': _AcceptedCell(23, 'lava'),
  'r2c3': _AcceptedCell(15, 'cobblestone'),
  'r3c0': _AcceptedCell(14, 'planks'),
  'r3c1': _AcceptedCell(null, 'glass-palette-reference'),
  'r3c2': _AcceptedCell(17, 'brick'),
  'r3c3': _AcceptedCell(24, 'tnt-side'),
};

void main() {
  _verifyLegacyFallback();
  final sourceBytes = _materializeAcceptedReference();
  final source = decodePng(sourceBytes);
  if (source == null) {
    throw StateError('Accepted reference is not a decodable PNG.');
  }
  if (source.width != _sourceWidth || source.height != _sourceHeight) {
    throw StateError(
      'Accepted reference must be ${_sourceWidth}x$_sourceHeight, got '
      '${source.width}x${source.height}.',
    );
  }

  final crops = <String, _CropResult>{};
  for (var row = 0; row < _rows.length; row++) {
    for (var column = 0; column < _columns.length; column++) {
      final id = 'r${row}c$column';
      final spec = _CropSpec(
        id: id,
        column: column,
        row: row,
        x: _columns[column].offset,
        y: _rows[row].offset,
        width: _columns[column].length,
        height: _rows[row].length,
        guard: 1,
      );
      spec.validate(source.width, source.height);
      crops[id] = _CropResult.fromSource(source, spec);
    }
  }

  final masters = <int, _MasterBuild>{};

  void accepted(int index, String cropId, {String postprocess = 'none'}) {
    var image = _copyImage(crops[cropId]!.normalized);
    switch (postprocess) {
      case 'none':
        break;
      case 'leaves-dark-hole-binary-alpha-v1':
        image = _authorLeavesAlpha(image);
      case 'constant-alpha-180':
        _setConstantAlpha(image, 180);
      case 'constant-alpha-230':
        _setConstantAlpha(image, 230);
      case 'remove-tnt-band-glyphs-v1':
        image = _sanitizeTntSide(image);
      default:
        throw StateError('Unknown accepted postprocess: $postprocess');
    }
    masters[index] = _MasterBuild(image, <String, Object?>{
      'algorithm': 'accepted-crop-integer-box-average-v1',
      'crop': cropId,
      'postprocess': postprocess,
    });
  }

  void original(
    int index,
    Image image, {
    required String algorithm,
    required List<String> paletteCrops,
    int? seed,
  }) {
    masters[index] = _MasterBuild(image, <String, Object?>{
      'algorithm': algorithm,
      'paletteCrops': paletteCrops,
      'seed': ?seed,
    });
  }

  accepted(0, 'r0c3');
  accepted(1, 'r0c2');
  accepted(2, 'r0c0');
  accepted(3, 'r0c1');
  accepted(4, 'r1c0');
  accepted(5, 'r1c1');
  accepted(6, 'r1c2');
  accepted(7, 'r1c3');
  accepted(8, 'r2c0', postprocess: 'leaves-dark-hole-binary-alpha-v1');
  accepted(9, 'r2c1', postprocess: 'constant-alpha-180');
  original(
    10,
    _makeBedrock(crops['r0c3']!.normalized),
    algorithm: 'original-clustered-bedrock-v1',
    paletteCrops: const ['r0c3'],
    seed: 0x10b0,
  );
  original(
    11,
    _makeOre(crops['r0c3']!.normalized, const _Rgb(42, 39, 37), 0x0c01),
    algorithm: 'original-diagonal-ore-veins-v1',
    paletteCrops: const ['r0c3'],
    seed: 0x0c01,
  );
  original(
    12,
    _makeOre(crops['r0c3']!.normalized, const _Rgb(204, 148, 100), 0x1a02),
    algorithm: 'original-diagonal-ore-veins-v1',
    paletteCrops: const ['r0c3', 'r0c2'],
    seed: 0x1a02,
  );
  original(
    13,
    _makeOre(crops['r0c3']!.normalized, const _Rgb(242, 190, 48), 0x6f03),
    algorithm: 'original-diagonal-ore-veins-v1',
    paletteCrops: const ['r0c3', 'r1c0'],
    seed: 0x6f03,
  );
  accepted(14, 'r3c0');
  accepted(15, 'r2c3');
  original(
    16,
    _makeGlass(crops['r3c1']!.normalized),
    algorithm: 'original-open-diagonal-glass-cutout-v1',
    paletteCrops: const ['r3c1'],
  );
  accepted(17, 'r3c2');
  original(
    18,
    _makeSponge(crops['r1c0']!.normalized),
    algorithm: 'original-porous-sponge-v1',
    paletteCrops: const ['r1c0'],
    seed: 0x5a18,
  );
  original(
    19,
    _makeFlower(
      stem: const _Rgb(65, 132, 48),
      petal: const _Rgb(246, 206, 47),
      center: const _Rgb(147, 92, 34),
      rose: false,
    ),
    algorithm: 'original-cross-flower-silhouette-v1',
    paletteCrops: const ['r0c0', 'r1c0'],
  );
  original(
    20,
    _makeFlower(
      stem: const _Rgb(58, 125, 48),
      petal: const _Rgb(190, 48, 45),
      center: const _Rgb(112, 31, 31),
      rose: true,
    ),
    algorithm: 'original-cross-flower-silhouette-v1',
    paletteCrops: const ['r0c0', 'r3c2'],
  );
  original(
    21,
    _makeMushroom(
      cap: const _Rgb(137, 93, 55),
      capLight: const _Rgb(179, 135, 86),
      spotted: false,
    ),
    algorithm: 'original-cross-mushroom-silhouette-v1',
    paletteCrops: const ['r0c2', 'r1c0'],
  );
  original(
    22,
    _makeMushroom(
      cap: const _Rgb(183, 45, 38),
      capLight: const _Rgb(230, 211, 175),
      spotted: true,
    ),
    algorithm: 'original-cross-mushroom-silhouette-v1',
    paletteCrops: const ['r3c2', 'r1c0'],
  );
  accepted(23, 'r2c2', postprocess: 'constant-alpha-230');
  accepted(24, 'r3c3', postprocess: 'remove-tnt-band-glyphs-v1');
  original(
    25,
    _makeTntTop(crops['r3c3']!.normalized),
    algorithm: 'original-radial-tnt-top-v1',
    paletteCrops: const ['r3c3', 'r3c2'],
    seed: 0x7a25,
  );
  original(
    26,
    _makeTntBottom(crops['r0c2']!.normalized),
    algorithm: 'original-wrapped-tnt-bottom-v1',
    paletteCrops: const ['r0c2', 'r3c3'],
    seed: 0x7b26,
  );
  original(
    27,
    _makeSapling(),
    algorithm: 'original-cross-sapling-silhouette-v1',
    paletteCrops: const ['r0c0', 'r1c2'],
  );
  original(
    28,
    _makeMetal(const _Rgb(214, 166, 42), const _Rgb(255, 224, 105), 0x6028),
    algorithm: 'original-faceted-metal-v1',
    paletteCrops: const ['r1c0', 'r1c3'],
    seed: 0x6028,
  );
  original(
    29,
    _makeMetal(const _Rgb(171, 178, 181), const _Rgb(232, 239, 239), 0x1a29),
    algorithm: 'original-faceted-metal-v1',
    paletteCrops: const ['r0c3', 'r3c1'],
    seed: 0x1a29,
  );

  const clothColors = <_Rgb>[
    _Rgb(220, 216, 202),
    _Rgb(170, 50, 48),
    _Rgb(204, 104, 39),
    _Rgb(215, 184, 49),
    _Rgb(92, 157, 52),
    _Rgb(51, 91, 166),
  ];
  for (var index = 30; index <= 35; index++) {
    original(
      index,
      _makeCloth(clothColors[index - 30], 0x0c00 + index),
      algorithm: 'original-offset-weave-cloth-v1',
      paletteCrops: const ['r0c0', 'r3c0', 'r3c2'],
      seed: 0x0c00 + index,
    );
  }
  original(
    36,
    _makeObsidian(crops['r0c3']!.normalized),
    algorithm: 'original-toroidal-violet-shards-obsidian-v1',
    paletteCrops: const ['r0c3'],
    seed: 0x0b51d1a,
  );

  _validateMasterSet(masters);
  final masterRecords = _writeMasters(masters);
  final output = _assembleAtlas(masters);
  final outputBytes = encodePng(output, level: 9);
  File(_outputPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(outputBytes, flush: true);

  final generatorBytes = File('bin/make_alpha_atlas.dart').readAsBytesSync();
  final cropRecords = <Map<String, Object?>>[];
  for (final id in crops.keys.toList()..sort()) {
    final crop = crops[id]!;
    final acceptedCell = _acceptedCells[id]!;
    cropRecords.add(<String, Object?>{
      'acceptedCell': acceptedCell.name,
      'acceptedTileIndex': acceptedCell.tileIndex,
      'guardPixels': crop.spec.guard,
      'id': id,
      'normalizedPngSha256': crop.normalizedPngSha256,
      'normalizedRgbaSha256': crop.normalizedRgbaSha256,
      'rawCropRgbaSha256': crop.rawCropRgbaSha256,
      'rawRect': crop.spec.rawRect,
      'sampledCropRgbaSha256': crop.sampledCropRgbaSha256,
      'sampledRect': crop.spec.sampledRect,
    });
  }

  final derivations = <String, Object?>{};
  for (var index = 0; index < _firstUnusedTile; index++) {
    final spec = masters[index]!.derivation;
    final key = index.toString().padLeft(2, '0');
    derivations[key] = <String, Object?>{
      'spec': spec,
      'specSha256': _jsonSha256(spec),
    };
  }

  final provenance = <String, Object?>{
    'approvedExtensions': <Map<String, Object?>>[
      <String, Object?>{
        'blockId': 33,
        'name': 'obsidian',
        'priorOutputSha256': _preObsidianAlphaAtlasSha256,
        'tileIndex': 36,
      },
    ],
    'crops': cropRecords,
    'derivations': derivations,
    'formatVersion': 1,
    'generator': <String, Object?>{
      'path': 'bin/make_alpha_atlas.dart',
      'sha256': sha256Hex(generatorBytes),
    },
    'legacyFallback': <String, Object?>{
      'approvedExtension': <String, Object?>{
        'block': 'obsidian',
        'priorAtlasSha256': _preObsidianLegacyAtlasSha256,
        'priorGeneratorSha256': _preObsidianLegacyGeneratorSha256,
        'tileIndex': 36,
      },
      'atlas': <String, Object?>{
        'path': 'assets/textures/atlas.png',
        'sha256': _legacyAtlasSha256,
      },
      'generator': <String, Object?>{
        'path': 'bin/make_atlas.dart',
        'sha256': _legacyGeneratorSha256,
      },
      'status':
          'pinned legacy fallback after the approved additive obsidian tile',
    },
    'masters': masterRecords,
    'output': <String, Object?>{
      'alphaModel': 'straight RGBA',
      'atlasSize': <String, int>{'height': _atlasSize, 'width': _atlasSize},
      'firstUnusedTile': _firstUnusedTile,
      'layout': 'row-major 16 by 16 tiles, each 16 by 16 pixels',
      'path': _outputPath,
      'rgbaSha256': sha256Hex(_rgbaBytes(output)),
      'sha256': sha256Hex(outputBytes),
      'unusedTiles': '37..255 transparent RGBA(0,0,0,0)',
    },
    'source': <String, Object?>{
      'acceptedStyleSummary':
          'Chunky 16x16-scale voxel pixel art with restrained earthy colors, '
          'soft value variation, readable natural materials, and simple '
          'directional top/side cues.',
      'artifactId': _artifactId,
      'generationId': _generationId,
      'height': _sourceHeight,
      'originalArtifactPath': _originalSourcePath,
      'originalPrompt': null,
      'originalPromptAvailability':
          'Unavailable from the ephemeral source task; no prompt was '
          'reconstructed or invented.',
      'path': _referencePath,
      'provider': 'openai',
      'providerTool': 'imagegen',
      'sha256': _sourceSha256,
      'sourceColorModel': '8-bit RGB, no alpha',
      'width': _sourceWidth,
    },
    'resampling': <String, Object?>{
      'algorithm': 'integer box average',
      'channelRounding': 'integer-half-up',
      'guardApplication':
          'inset each supplied raw crop by one pixel on all four sides',
      'output': '16x16 RGBA with source alpha initialized to 255',
      'version': 1,
    },
  };
  final encoded = const JsonEncoder.withIndent(
    '  ',
  ).convert(_sortJson(provenance));
  File(_provenancePath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('$encoded\n', flush: true);
}

void _verifyLegacyFallback() {
  final generator = File('bin/make_atlas.dart');
  final atlas = File('assets/textures/atlas.png');
  if (!generator.existsSync() || !atlas.existsSync()) {
    throw StateError('Immutable legacy atlas fallback is missing.');
  }
  final generatorHash = sha256Hex(generator.readAsBytesSync());
  final atlasHash = sha256Hex(atlas.readAsBytesSync());
  if (generatorHash != _legacyGeneratorSha256 ||
      atlasHash != _legacyAtlasSha256) {
    throw StateError(
      'Immutable legacy fallback changed: generator=$generatorHash, '
      'atlas=$atlasHash.',
    );
  }
}

Uint8List _materializeAcceptedReference() {
  final reference = File(_referencePath);
  reference.parent.createSync(recursive: true);
  if (!reference.existsSync()) {
    final original = File(_originalSourcePath);
    if (!original.existsSync()) {
      throw StateError(
        'Accepted reference is absent and original artifact is unavailable: '
        '$_originalSourcePath',
      );
    }
    final originalBytes = original.readAsBytesSync();
    final originalHash = sha256Hex(originalBytes);
    if (originalHash != _sourceSha256) {
      throw StateError(
        'Original accepted artifact hash mismatch: $originalHash.',
      );
    }
    original.copySync(reference.path);
  }
  final bytes = reference.readAsBytesSync();
  final hash = sha256Hex(bytes);
  if (hash != _sourceSha256) {
    throw StateError('Accepted reference hash mismatch: $hash.');
  }
  return bytes;
}

List<Map<String, Object?>> _writeMasters(Map<int, _MasterBuild> masters) {
  final directory = Directory(_mastersPath)..createSync(recursive: true);
  final expectedNames = <String>{};
  final records = <Map<String, Object?>>[];
  for (var index = 0; index < _firstUnusedTile; index++) {
    final name = _tileNames[index];
    final filename = '${index.toString().padLeft(2, '0')}-$name.png';
    expectedNames.add(filename);
    final path = '$_mastersPath/$filename';
    final image = masters[index]!.image;
    final bytes = encodePng(image, level: 9);
    File(path).writeAsBytesSync(bytes, flush: true);
    records.add(<String, Object?>{
      'alphaCategory': _alphaCategory(index),
      'derivationSpecSha256': _jsonSha256(masters[index]!.derivation),
      'index': index,
      'name': name,
      'path': path,
      'rgbaSha256': sha256Hex(_rgbaBytes(image)),
      'sha256': sha256Hex(bytes),
    });
  }
  final unexpected =
      directory
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where(
            (name) => name.endsWith('.png') && !expectedNames.contains(name),
          )
          .toList()
        ..sort();
  if (unexpected.isNotEmpty) {
    throw StateError('Unexpected master PNGs: ${unexpected.join(', ')}');
  }
  return records;
}

String _alphaCategory(int index) {
  if (index == 9) return 'constant-180';
  if (index == 23) return 'constant-230';
  if (index == 8 ||
      index == 16 ||
      (index >= 19 && index <= 22) ||
      index == 27) {
    return 'binary-cutout-0-or-255';
  }
  return 'opaque-255';
}

Image _assembleAtlas(Map<int, _MasterBuild> masters) {
  final atlas = Image(width: _atlasSize, height: _atlasSize, numChannels: 4)
    ..clear(ColorRgba8(0, 0, 0, 0));
  for (var index = 0; index < _firstUnusedTile; index++) {
    final master = masters[index]!.image;
    final originX = (index & 15) * _tileSize;
    final originY = (index >> 4) * _tileSize;
    for (var y = 0; y < _tileSize; y++) {
      for (var x = 0; x < _tileSize; x++) {
        final pixel = master.getPixel(x, y);
        atlas.setPixelRgba(
          originX + x,
          originY + y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          pixel.a.toInt(),
        );
      }
    }
  }
  return atlas;
}

void _validateMasterSet(Map<int, _MasterBuild> masters) {
  final indices = masters.keys.toList()..sort();
  final expected = List<int>.generate(_firstUnusedTile, (index) => index);
  if (!_listEquals(indices, expected)) {
    throw StateError(
      'Master indices must be exactly 0..${_firstUnusedTile - 1}, '
      'got $indices.',
    );
  }
  for (final entry in masters.entries) {
    final image = entry.value.image;
    if (image.width != _tileSize ||
        image.height != _tileSize ||
        image.numChannels != 4) {
      throw StateError(
        'Master ${entry.key} must be 16x16 RGBA, got '
        '${image.width}x${image.height} with ${image.numChannels} channels.',
      );
    }
    final alphas = <int>{};
    for (final pixel in image) {
      alphas.add(pixel.a.toInt());
    }
    final category = _alphaCategory(entry.key);
    if (category == 'opaque-255' && !_setEquals(alphas, const {255})) {
      throw StateError('Master ${entry.key} must be opaque, got $alphas.');
    }
    if (category == 'constant-180' && !_setEquals(alphas, const {180})) {
      throw StateError('Water master alpha must be 180, got $alphas.');
    }
    if (category == 'constant-230' && !_setEquals(alphas, const {230})) {
      throw StateError('Lava master alpha must be 230, got $alphas.');
    }
    if (category == 'binary-cutout-0-or-255' &&
        !_setEquals(alphas, const {0, 255})) {
      throw StateError(
        'Cutout master ${entry.key} must contain alpha 0 and 255, got $alphas.',
      );
    }
    if (category == 'binary-cutout-0-or-255') {
      for (final pixel in image) {
        if (pixel.a.toInt() == 0 &&
            pixel.r.toInt() == 0 &&
            pixel.g.toInt() == 0 &&
            pixel.b.toInt() == 0) {
          throw StateError(
            'Cutout master ${entry.key} retains black RGB under alpha 0.',
          );
        }
      }
    }
  }
}

Image _authorLeavesAlpha(Image source) {
  final image = _copyImage(source);
  var holes = 0;
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final luma = (3 * r + 6 * g + b) ~/ 10;
      final transparent = luma < 54 && g < 78;
      image.setPixelRgba(x, y, r, g, b, transparent ? 0 : 255);
      if (transparent) holes++;
    }
  }
  if (holes < 8 || holes > 160) {
    throw StateError('Leaves dark-hole mask is implausible: $holes holes.');
  }
  _bleedTransparentRgb(image);
  return image;
}

void _setConstantAlpha(Image image, int alpha) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      image.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        alpha,
      );
    }
  }
}

Image _sanitizeTntSide(Image source) {
  final image = _copyImage(source);
  var bestStart = 4;
  var bestScore = -0x7fffffff;
  for (var start = 3; start <= 9; start++) {
    var score = 0;
    for (var y = start; y < start + 4; y++) {
      for (var x = 0; x < _tileSize; x++) {
        final pixel = image.getPixel(x, y);
        score += pixel.g.toInt() + pixel.b.toInt() - pixel.r.toInt();
      }
    }
    if (score > bestScore) {
      bestScore = score;
      bestStart = start;
    }
  }
  final candidates = <_Rgb>[];
  for (var y = bestStart; y < bestStart + 4; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final rgb = _rgbAt(image, x, y);
      final maxChannel = _max3(rgb.r, rgb.g, rgb.b);
      final minChannel = _min3(rgb.r, rgb.g, rgb.b);
      if (minChannel > 125 && maxChannel - minChannel < 85) {
        candidates.add(rgb);
      }
    }
  }
  final band = candidates.isEmpty
      ? const _Rgb(205, 197, 184)
      : _averageColors(candidates);
  for (var y = bestStart; y < bestStart + 4; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final delta = ((x ~/ 3 + y) & 1) == 0 ? 5 : -5;
      _setRgb(image, x, y, band.shift(delta), 255);
    }
  }
  return image;
}

Image _makeBedrock(Image stone) {
  final image = _opaqueImage();
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final source = _rgbAt(stone, x, y);
      final luma = (source.r * 3 + source.g * 6 + source.b) ~/ 10;
      final cluster = _noiseSigned(x ~/ 2, y ~/ 2, 0x10b0, 17);
      final grain = _noiseSigned(x, y, 0x10b1, 8);
      final value = _clamp((luma * 47) ~/ 100 + cluster + grain, 24, 104);
      _setRgb(image, x, y, _Rgb(value, value - 2, value - 4), 255);
    }
  }
  return image;
}

Image _makeOre(Image stone, _Rgb ore, int seed) {
  final image = _copyImage(stone);
  for (var y = 0; y < _tileSize; y++) {
    final path = 2 + ((y * 7 + (seed & 15) + (y ~/ 3) * 3) % 12);
    for (var x = 0; x < _tileSize; x++) {
      final branch = y >= 4 && y <= 12 && x == 13 - (y ~/ 2);
      final fleck =
          (x == path && ((y + seed) & 1) == 0) ||
          (x == path + 1 && y % 5 == 1) ||
          branch ||
          (_hash2(x, y, seed) % 97 < 4 && x > 1 && x < 14 && y > 1 && y < 14);
      if (fleck) {
        final delta = _noiseSigned(x, y, seed ^ 0x45a1, 18);
        _setRgb(image, x, y, ore.shift(delta), 255);
      } else {
        final source = _rgbAt(stone, x, y);
        _setRgb(image, x, y, source.shift(-4), 255);
      }
    }
  }
  return image;
}

Image _makeGlass(Image paletteReference) {
  final image = Image(width: _tileSize, height: _tileSize, numChannels: 4)
    ..clear(ColorRgba8(0, 0, 0, 0));
  final bright = <_Rgb>[];
  final all = <_Rgb>[];
  for (final pixel in paletteReference) {
    final rgb = _Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    all.add(rgb);
    if ((rgb.r + rgb.g + rgb.b) ~/ 3 > 190) bright.add(rgb);
  }
  final body = _averageColors(all).shift(12);
  final highlight = bright.isEmpty
      ? const _Rgb(218, 239, 244)
      : _averageColors(bright).shift(8);
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final mainSlash = x + y == 14 && x != 4 && x != 10;
      final upperShard = x + y == 7 && x >= 1 && x <= 5;
      final lowerShard = x + y == 22 && x >= 9 && x <= 13;
      final glint =
          (x == 12 && y == 3) ||
          (x == 3 && y == 11) ||
          (x == 6 && y == 5) ||
          (x == 9 && y == 9);
      final opaque = mainSlash || upperShard || lowerShard || glint;
      _setRgb(image, x, y, opaque ? highlight : body, opaque ? 255 : 0);
    }
  }
  _bleedTransparentRgb(image);
  return image;
}

Image _makeSponge(Image sand) {
  final image = _opaqueImage();
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final source = _rgbAt(sand, x, y);
      final luma = (source.r * 3 + source.g * 6 + source.b) ~/ 10;
      final pore = _hash2(x ~/ 2, y ~/ 2, 0x5a18) % 9 == 0;
      final grain = _noiseSigned(x, y, 0x5a19, 8);
      final base = pore
          ? _Rgb(128 + grain, 104 + grain, 25)
          : _Rgb(
              _clamp(165 + luma ~/ 4 + grain, 0, 255),
              _clamp(139 + luma ~/ 5 + grain, 0, 255),
              _clamp(28 + luma ~/ 12 + grain, 0, 255),
            );
      _setRgb(image, x, y, base, 255);
    }
  }
  return image;
}

Image _makeFlower({
  required _Rgb stem,
  required _Rgb petal,
  required _Rgb center,
  required bool rose,
}) {
  final image = _transparentImage();
  for (var y = 7; y <= 14; y++) {
    _setRgb(image, 8, y, stem.shift((y & 1) == 0 ? 6 : -5), 255);
  }
  for (final point in const <_Point>[
    _Point(6, 10),
    _Point(7, 10),
    _Point(9, 11),
    _Point(10, 11),
    _Point(7, 13),
    _Point(9, 13),
  ]) {
    _setRgb(image, point.x, point.y, stem.shift(-9), 255);
  }
  final petals = rose
      ? const <_Point>[
          _Point(7, 3),
          _Point(8, 3),
          _Point(9, 3),
          _Point(6, 4),
          _Point(7, 4),
          _Point(8, 4),
          _Point(9, 4),
          _Point(10, 4),
          _Point(7, 5),
          _Point(8, 5),
          _Point(9, 5),
          _Point(8, 6),
        ]
      : const <_Point>[
          _Point(8, 2),
          _Point(6, 3),
          _Point(8, 3),
          _Point(10, 3),
          _Point(5, 5),
          _Point(6, 5),
          _Point(7, 5),
          _Point(8, 5),
          _Point(9, 5),
          _Point(10, 5),
          _Point(11, 5),
          _Point(6, 7),
          _Point(8, 7),
          _Point(10, 7),
        ];
  for (final point in petals) {
    _setRgb(image, point.x, point.y, petal, 255);
  }
  _setRgb(image, 8, 5, center, 255);
  if (rose) _setRgb(image, 8, 4, center.shift(12), 255);
  _bleedTransparentRgb(image);
  return image;
}

Image _makeMushroom({
  required _Rgb cap,
  required _Rgb capLight,
  required bool spotted,
}) {
  final image = _transparentImage();
  for (var y = 8; y <= 14; y++) {
    for (var x = 7; x <= 9; x++) {
      _setRgb(
        image,
        x,
        y,
        const _Rgb(205, 186, 145).shift((x + y).isEven ? 6 : -7),
        255,
      );
    }
  }
  for (var y = 3; y <= 9; y++) {
    final halfWidth = y <= 4 ? y - 1 : (y <= 7 ? 6 : 5);
    for (var x = 8 - halfWidth; x <= 8 + halfWidth; x++) {
      if (x >= 1 && x < 15) {
        final edge = x == 8 - halfWidth || x == 8 + halfWidth || y == 9;
        _setRgb(image, x, y, edge ? cap.shift(-22) : cap, 255);
      }
    }
  }
  if (spotted) {
    for (final point in const <_Point>[
      _Point(5, 5),
      _Point(10, 4),
      _Point(12, 7),
      _Point(7, 8),
    ]) {
      _setRgb(image, point.x, point.y, capLight, 255);
    }
  } else {
    for (var x = 4; x <= 12; x += 2) {
      _setRgb(image, x, 6 + (x & 1), capLight, 255);
    }
  }
  _bleedTransparentRgb(image);
  return image;
}

Image _makeTntTop(Image side) {
  final image = _opaqueImage();
  final red = _averageRegion(side, 0, 0, 16, 5);
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final dx = x - 7;
      final dy = y - 7;
      final radius = dx.abs() + dy.abs();
      final spoke = x == 7 || x == 8 || y == 7 || y == 8;
      final ring = radius >= 7 && radius <= 9;
      final delta = spoke ? 24 : (ring ? -24 : _noiseSigned(x, y, 0x7a25, 9));
      _setRgb(image, x, y, red.shift(delta), 255);
    }
  }
  for (final point in const <_Point>[
    _Point(7, 7),
    _Point(8, 7),
    _Point(7, 8),
    _Point(8, 8),
  ]) {
    _setRgb(image, point.x, point.y, const _Rgb(64, 48, 38), 255);
  }
  return image;
}

Image _makeTntBottom(Image dirt) {
  final image = _opaqueImage();
  final average = _averageImage(dirt);
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final diagonal = ((x + y) ~/ 3).isEven ? 10 : -9;
      final grain = _noiseSigned(x, y, 0x7b26, 7);
      _setRgb(image, x, y, average.shift(diagonal + grain), 255);
    }
  }
  for (final point in const <_Point>[
    _Point(4, 4),
    _Point(11, 4),
    _Point(4, 11),
    _Point(11, 11),
  ]) {
    _setRgb(image, point.x, point.y, const _Rgb(112, 62, 42), 255);
  }
  return image;
}

Image _makeSapling() {
  final image = _transparentImage();
  for (var y = 6; y <= 14; y++) {
    _setRgb(image, 8, y, const _Rgb(105, 72, 37), 255);
  }
  for (final point in const <_Point>[
    _Point(7, 8),
    _Point(6, 7),
    _Point(9, 10),
    _Point(10, 9),
    _Point(7, 12),
    _Point(6, 11),
  ]) {
    _setRgb(image, point.x, point.y, const _Rgb(104, 72, 37), 255);
  }
  for (final point in const <_Point>[
    _Point(7, 3),
    _Point(8, 2),
    _Point(9, 3),
    _Point(6, 4),
    _Point(8, 4),
    _Point(10, 4),
    _Point(5, 6),
    _Point(6, 6),
    _Point(7, 6),
    _Point(9, 7),
    _Point(10, 7),
    _Point(11, 7),
    _Point(5, 10),
    _Point(6, 10),
    _Point(10, 11),
    _Point(11, 11),
  ]) {
    final delta = ((point.x + point.y) & 1) == 0 ? 10 : -8;
    _setRgb(image, point.x, point.y, const _Rgb(59, 130, 48).shift(delta), 255);
  }
  _bleedTransparentRgb(image);
  return image;
}

Image _makeMetal(_Rgb base, _Rgb highlight, int seed) {
  final image = _opaqueImage();
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final diagonal = x - y;
      final facet = diagonal > 4
          ? 18
          : (diagonal < -5 ? -20 : (((x + y) ~/ 5).isEven ? 7 : -7));
      final grain = _noiseSigned(x, y, seed, 5);
      var color = base.shift(facet + grain);
      if ((x + y == 8 && x >= 2 && x <= 6) || (x == 11 && y >= 8 && y <= 11)) {
        color = highlight.shift(grain);
      }
      _setRgb(image, x, y, color, 255);
    }
  }
  return image;
}

Image _makeCloth(_Rgb base, int seed) {
  final image = _opaqueImage();
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      final warp = (x & 1) == 0 ? 7 : -5;
      final weft = (y & 3) == 0 ? -4 : 3;
      final knot = ((x + 2 * y + seed) % 11 == 0) ? 8 : 0;
      _setRgb(image, x, y, base.shift(warp + weft + knot), 255);
    }
  }
  return image;
}

Image _makeObsidian(Image stone) {
  const seed = 0x0b51d1a;
  const shardCenters = <_Point>[
    _Point(1, 2),
    _Point(7, 0),
    _Point(12, 4),
    _Point(15, 9),
    _Point(10, 13),
    _Point(3, 12),
  ];
  const shardBias = <int>[-4, 3, -1, 5, -3, 1];

  final stoneAverage = _averageImage(stone);
  final stoneLuma =
      (stoneAverage.r * 3 + stoneAverage.g * 6 + stoneAverage.b) ~/ 10;
  final baseLuma = _clamp((stoneLuma * 31) ~/ 100, 27, 40);
  final body = _Rgb(baseLuma, baseLuma - 6, baseLuma + 11);
  final fracture = _Rgb(baseLuma + 19, baseLuma + 7, baseLuma + 31);
  final glint = _Rgb(baseLuma + 28, baseLuma + 15, baseLuma + 43);
  final image = _opaqueImage();

  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      var nearest = 0x7fffffff;
      var secondNearest = 0x7fffffff;
      var shard = 0;
      for (var index = 0; index < shardCenters.length; index++) {
        final center = shardCenters[index];
        final rawDx = (x - center.x).abs();
        final rawDy = (y - center.y).abs();
        final dx = rawDx > _tileSize ~/ 2 ? _tileSize - rawDx : rawDx;
        final dy = rawDy > _tileSize ~/ 2 ? _tileSize - rawDy : rawDy;
        final distance = dx * dx + dy * dy;
        if (distance < nearest) {
          secondNearest = nearest;
          nearest = distance;
          shard = index;
        } else if (distance < secondNearest) {
          secondNearest = distance;
        }
      }

      final coarse = _noiseSigned(x ~/ 2, y ~/ 2, seed, 4);
      final boundary = secondNearest - nearest <= 5;
      final highlight =
          !boundary && nearest <= 2 && _hash2(x, y, seed ^ 0x6117) % 5 == 0;
      final color = highlight
          ? glint.shift(coarse)
          : boundary
          ? fracture.shift(coarse)
          : body.shift(shardBias[shard] + coarse);
      _setRgb(image, x, y, color, 255);
    }
  }
  _closeOpaqueTileEdges(image);
  return image;
}

void _closeOpaqueTileEdges(Image image) {
  for (var y = 0; y < _tileSize; y++) {
    _setRgb(image, _tileSize - 1, y, _rgbAt(image, 0, y), 255);
  }
  for (var x = 0; x < _tileSize; x++) {
    _setRgb(image, x, _tileSize - 1, _rgbAt(image, x, 0), 255);
  }
}

Image _opaqueImage() =>
    Image(width: _tileSize, height: _tileSize, numChannels: 4)
      ..clear(ColorRgba8(0, 0, 0, 255));

Image _transparentImage() =>
    Image(width: _tileSize, height: _tileSize, numChannels: 4)
      ..clear(ColorRgba8(0, 0, 0, 0));

void _bleedTransparentRgb(Image image) {
  final opaque = <_OpaquePixel>[];
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      if (pixel.a.toInt() != 0) {
        opaque.add(_OpaquePixel(x, y, _rgbAt(image, x, y)));
      }
    }
  }
  if (opaque.isEmpty) {
    throw StateError('Cannot bleed a fully transparent image.');
  }
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a.toInt() != 0) continue;
      _OpaquePixel? nearest;
      var nearestDistance = 0x7fffffff;
      for (final candidate in opaque) {
        final dx = candidate.x - x;
        final dy = candidate.y - y;
        final distance = dx * dx + dy * dy;
        if (distance < nearestDistance) {
          nearest = candidate;
          nearestDistance = distance;
        }
      }
      _setRgb(image, x, y, nearest!.rgb, 0);
    }
  }
}

Image _copyImage(Image source) {
  final result = Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      result.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        pixel.a.toInt(),
      );
    }
  }
  return result;
}

Uint8List _rgbaBytes(Image image) {
  final bytes = Uint8List(image.width * image.height * 4);
  var offset = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      bytes[offset++] = pixel.r.toInt();
      bytes[offset++] = pixel.g.toInt();
      bytes[offset++] = pixel.b.toInt();
      bytes[offset++] = pixel.a.toInt();
    }
  }
  return bytes;
}

Uint8List _cropRgbaBytes(Image source, int x, int y, int width, int height) {
  final bytes = Uint8List(width * height * 4);
  var offset = 0;
  for (var row = y; row < y + height; row++) {
    for (var column = x; column < x + width; column++) {
      final pixel = source.getPixel(column, row);
      bytes[offset++] = pixel.r.toInt();
      bytes[offset++] = pixel.g.toInt();
      bytes[offset++] = pixel.b.toInt();
      bytes[offset++] = pixel.a.toInt();
    }
  }
  return bytes;
}

_Rgb _rgbAt(Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  return _Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
}

void _setRgb(Image image, int x, int y, _Rgb color, int alpha) {
  image.setPixelRgba(
    x,
    y,
    _clamp(color.r, 0, 255),
    _clamp(color.g, 0, 255),
    _clamp(color.b, 0, 255),
    alpha,
  );
}

_Rgb _averageImage(Image image) {
  final colors = <_Rgb>[];
  for (final pixel in image) {
    colors.add(_Rgb(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()));
  }
  return _averageColors(colors);
}

_Rgb _averageRegion(Image image, int x, int y, int width, int height) {
  final colors = <_Rgb>[];
  for (var row = y; row < y + height; row++) {
    for (var column = x; column < x + width; column++) {
      colors.add(_rgbAt(image, column, row));
    }
  }
  return _averageColors(colors);
}

_Rgb _averageColors(List<_Rgb> colors) {
  if (colors.isEmpty) throw StateError('Cannot average an empty palette.');
  var red = 0;
  var green = 0;
  var blue = 0;
  for (final color in colors) {
    red += color.r;
    green += color.g;
    blue += color.b;
  }
  return _Rgb(
    red ~/ colors.length,
    green ~/ colors.length,
    blue ~/ colors.length,
  );
}

int _hash2(int x, int y, int seed) {
  var value = (seed ^ (x * 0x45d9f3b) ^ (y * 0x119de1f3)) & 0xffffffff;
  value = ((value ^ (value >>> 16)) * 0x45d9f3b) & 0xffffffff;
  value = ((value ^ (value >>> 16)) * 0x45d9f3b) & 0xffffffff;
  return (value ^ (value >>> 16)) & 0xffffffff;
}

int _noiseSigned(int x, int y, int seed, int amplitude) =>
    _hash2(x, y, seed) % (amplitude * 2 + 1) - amplitude;

int _clamp(int value, int minimum, int maximum) =>
    value < minimum ? minimum : (value > maximum ? maximum : value);

int _min3(int a, int b, int c) {
  final ab = a < b ? a : b;
  return ab < c ? ab : c;
}

int _max3(int a, int b, int c) {
  final ab = a > b ? a : b;
  return ab > c ? ab : c;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

String _jsonSha256(Object? value) =>
    sha256Hex(utf8.encode(jsonEncode(_sortJson(value))));

Object? _sortJson(Object? value) {
  if (value is Map) {
    final result = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      result[entry.key.toString()] = _sortJson(entry.value);
    }
    return result;
  }
  if (value is List) return value.map(_sortJson).toList();
  return value;
}

/// Pure-Dart SHA-256 used so the asset pipeline has no extra dependency.
String sha256Hex(List<int> input) {
  const initial = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  const constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final bitLength = input.length * 8;
  final paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
  final message = Uint8List(paddedLength)..setRange(0, input.length, input);
  message[input.length] = 0x80;
  for (var index = 0; index < 8; index++) {
    message[paddedLength - 1 - index] = (bitLength >>> (index * 8)) & 0xff;
  }
  final hash = List<int>.from(initial);
  final words = Uint32List(64);
  for (var offset = 0; offset < message.length; offset += 64) {
    for (var index = 0; index < 16; index++) {
      final base = offset + index * 4;
      words[index] =
          (message[base] << 24) |
          (message[base + 1] << 16) |
          (message[base + 2] << 8) |
          message[base + 3];
    }
    for (var index = 16; index < 64; index++) {
      final s0 =
          _rotateRight(words[index - 15], 7) ^
          _rotateRight(words[index - 15], 18) ^
          (words[index - 15] >>> 3);
      final s1 =
          _rotateRight(words[index - 2], 17) ^
          _rotateRight(words[index - 2], 19) ^
          (words[index - 2] >>> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }
    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var index = 0; index < 64; index++) {
      final sigma1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choice = (e & f) ^ ((~e) & g);
      final temp1 =
          (h + sigma1 + choice + constants[index] + words[index]) & 0xffffffff;
      final sigma0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sigma0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }
  return hash.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}

int _rotateRight(int value, int count) =>
    ((value >>> count) | (value << (32 - count))) & 0xffffffff;

final class _AxisSpan {
  const _AxisSpan(this.offset, this.length);

  final int offset;
  final int length;
}

final class _AcceptedCell {
  const _AcceptedCell(this.tileIndex, this.name);

  final int? tileIndex;
  final String name;
}

final class _CropSpec {
  const _CropSpec({
    required this.id,
    required this.column,
    required this.row,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.guard,
  });

  final String id;
  final int column;
  final int row;
  final int x;
  final int y;
  final int width;
  final int height;
  final int guard;

  int get sampledX => x + guard;
  int get sampledY => y + guard;
  int get sampledWidth => width - guard * 2;
  int get sampledHeight => height - guard * 2;

  Map<String, int> get rawRect => <String, int>{
    'height': height,
    'width': width,
    'x': x,
    'y': y,
  };

  Map<String, int> get sampledRect => <String, int>{
    'height': sampledHeight,
    'width': sampledWidth,
    'x': sampledX,
    'y': sampledY,
  };

  void validate(int sourceWidth, int sourceHeight) {
    if (guard < 0 || sampledWidth < _tileSize || sampledHeight < _tileSize) {
      throw StateError('$id has an invalid crop guard.');
    }
    if (x < 0 ||
        y < 0 ||
        x + width > sourceWidth ||
        y + height > sourceHeight) {
      throw StateError('$id raw crop is outside the source image.');
    }
    if (sampledX < x ||
        sampledY < y ||
        sampledX + sampledWidth > x + width ||
        sampledY + sampledHeight > y + height) {
      throw StateError('$id sampled crop is outside its raw crop.');
    }
  }
}

final class _CropResult {
  _CropResult({
    required this.spec,
    required this.normalized,
    required this.rawCropRgbaSha256,
    required this.sampledCropRgbaSha256,
    required this.normalizedRgbaSha256,
    required this.normalizedPngSha256,
  });

  factory _CropResult.fromSource(Image source, _CropSpec spec) {
    final normalized = Image(
      width: _tileSize,
      height: _tileSize,
      numChannels: 4,
    );
    for (var outputY = 0; outputY < _tileSize; outputY++) {
      final sourceY0 =
          spec.sampledY + outputY * spec.sampledHeight ~/ _tileSize;
      final sourceY1 =
          spec.sampledY + (outputY + 1) * spec.sampledHeight ~/ _tileSize;
      for (var outputX = 0; outputX < _tileSize; outputX++) {
        final sourceX0 =
            spec.sampledX + outputX * spec.sampledWidth ~/ _tileSize;
        final sourceX1 =
            spec.sampledX + (outputX + 1) * spec.sampledWidth ~/ _tileSize;
        var red = 0;
        var green = 0;
        var blue = 0;
        var count = 0;
        for (var y = sourceY0; y < sourceY1; y++) {
          for (var x = sourceX0; x < sourceX1; x++) {
            final pixel = source.getPixel(x, y);
            red += pixel.r.toInt();
            green += pixel.g.toInt();
            blue += pixel.b.toInt();
            count++;
          }
        }
        normalized.setPixelRgba(
          outputX,
          outputY,
          (red + count ~/ 2) ~/ count,
          (green + count ~/ 2) ~/ count,
          (blue + count ~/ 2) ~/ count,
          255,
        );
      }
    }
    final normalizedRgba = _rgbaBytes(normalized);
    final normalizedPng = encodePng(normalized, level: 9);
    return _CropResult(
      spec: spec,
      normalized: normalized,
      rawCropRgbaSha256: sha256Hex(
        _cropRgbaBytes(source, spec.x, spec.y, spec.width, spec.height),
      ),
      sampledCropRgbaSha256: sha256Hex(
        _cropRgbaBytes(
          source,
          spec.sampledX,
          spec.sampledY,
          spec.sampledWidth,
          spec.sampledHeight,
        ),
      ),
      normalizedRgbaSha256: sha256Hex(normalizedRgba),
      normalizedPngSha256: sha256Hex(normalizedPng),
    );
  }

  final _CropSpec spec;
  final Image normalized;
  final String rawCropRgbaSha256;
  final String sampledCropRgbaSha256;
  final String normalizedRgbaSha256;
  final String normalizedPngSha256;
}

final class _MasterBuild {
  const _MasterBuild(this.image, this.derivation);

  final Image image;
  final Map<String, Object?> derivation;
}

final class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  _Rgb shift(int delta) => _Rgb(
    _clamp(r + delta, 0, 255),
    _clamp(g + delta, 0, 255),
    _clamp(b + delta, 0, 255),
  );
}

final class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;
}

final class _OpaquePixel {
  const _OpaquePixel(this.x, this.y, this.rgb);

  final int x;
  final int y;
  final _Rgb rgb;
}
