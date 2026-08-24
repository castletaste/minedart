import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';
import 'package:minedart_core/minedart_core.dart';

import '../../bin/make_alpha_atlas.dart' show sha256Hex;

const _atlasPath = 'assets/textures/atlas_alpha.png';
const _sourceRoot = 'tool/atlas_sources/default_alpha';
const _referencePath = '$_sourceRoot/reference/accepted-sheet.png';
const _provenancePath = '$_sourceRoot/atlas.provenance.json';
const _mastersPath = '$_sourceRoot/masters';
const _sourceSha256 =
    '390534263eca3f5becc510146361402f085ecdb65acad94617e77b7ad13c7c02';
const _legacyGeneratorSha256 =
    'd685041766bb869f336028575037778bbd8fd75a04cccf893b74f6d3fa7d4134';
const _legacyAtlasSha256 =
    '5bed18299c2bb9eb14c6e8caedf9c261ff43bb402484f4d65c0ba2c1f4c624ad';

const _masterNames = <String>[
  '00-stone.png',
  '01-dirt.png',
  '02-grass-top.png',
  '03-grass-side.png',
  '04-sand.png',
  '05-gravel.png',
  '06-log-side.png',
  '07-log-top.png',
  '08-leaves.png',
  '09-water.png',
  '10-bedrock.png',
  '11-ore-coal.png',
  '12-ore-iron.png',
  '13-ore-gold.png',
  '14-planks.png',
  '15-cobblestone.png',
  '16-glass.png',
  '17-brick.png',
  '18-sponge.png',
  '19-flower-dandelion.png',
  '20-flower-rose.png',
  '21-mushroom-brown.png',
  '22-mushroom-red.png',
  '23-lava.png',
  '24-tnt-side.png',
  '25-tnt-top.png',
  '26-tnt-bottom.png',
  '27-sapling.png',
  '28-gold-block.png',
  '29-iron-block.png',
  '30-cloth-white.png',
  '31-cloth-red.png',
  '32-cloth-orange.png',
  '33-cloth-yellow.png',
  '34-cloth-lime.png',
  '35-cloth-blue.png',
];

void main() {
  late Image atlas;
  late Map<String, Object?> provenance;

  setUpAll(() async {
    expect(
      sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      reason: 'the dependency-free SHA-256 implementation needs a known vector',
    );

    await _runGenerator();
    final firstHashes = _generatedHashes();
    await _runGenerator();
    final secondHashes = _generatedHashes();
    expect(
      secondHashes,
      firstHashes,
      reason: 'two complete regenerations must be byte-identical',
    );

    atlas = _decode(_atlasPath);
    provenance = (jsonDecode(File(_provenancePath).readAsStringSync()) as Map)
        .cast<String, Object?>();
  });

  test('accepted reference is the exact RGB artifact copy', () {
    final bytes = File(_referencePath).readAsBytesSync();
    expect(sha256Hex(bytes), _sourceSha256);
    final reference = _decode(_referencePath);
    expect((reference.width, reference.height), (1254, 1254));
    expect(reference.numChannels, 3);

    const originalPath =
        '/Users/savva/.codex/generated_images/'
        '01a0353c-e237-78a2-84fc-bdb50d206ba7/'
        'exec-ef38e19a-00ec-4fad-80a3-9ddc5258e2c5.png';
    final original = File(originalPath);
    if (original.existsSync()) {
      expect(original.readAsBytesSync(), bytes);
    }

    final referenceRecord = provenance['source']! as Map<String, Object?>;
    expect(referenceRecord['provider'], 'openai');
    expect(referenceRecord['providerTool'], 'imagegen');
    expect(referenceRecord['sha256'], _sourceSha256);
    expect(
      referenceRecord['generationId'],
      '01a0353c-e237-78a2-84fc-bdb50d206ba7',
    );
    expect(
      referenceRecord['artifactId'],
      'exec-ef38e19a-00ec-4fad-80a3-9ddc5258e2c5',
    );
    expect(referenceRecord['originalPrompt'], isNull);
    expect(
      referenceRecord['originalPromptAvailability'],
      contains('no prompt was reconstructed or invented'),
    );
  });

  test('guarded crops are exact, contained, and hash-recorded', () {
    const columns = <(int, int)>[(20, 293), (329, 292), (638, 292), (947, 289)];
    const rows = <(int, int)>[(19, 295), (332, 278), (629, 291), (937, 297)];
    const acceptedIndices = <int?>[
      2,
      3,
      1,
      0,
      4,
      5,
      6,
      7,
      8,
      9,
      23,
      15,
      14,
      null,
      17,
      24,
    ];
    final crops = (provenance['crops']! as List).cast<Map<String, Object?>>();
    expect(crops, hasLength(16));
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        final crop = crops[row * 4 + column];
        final raw = (crop['rawRect']! as Map).cast<String, Object?>();
        final sampled = (crop['sampledRect']! as Map).cast<String, Object?>();
        expect(crop['id'], 'r${row}c$column');
        expect(crop['acceptedTileIndex'], acceptedIndices[row * 4 + column]);
        expect(crop['guardPixels'], 1);
        expect(raw, <String, Object?>{
          'height': rows[row].$2,
          'width': columns[column].$2,
          'x': columns[column].$1,
          'y': rows[row].$1,
        });
        expect(sampled, <String, Object?>{
          'height': rows[row].$2 - 2,
          'width': columns[column].$2 - 2,
          'x': columns[column].$1 + 1,
          'y': rows[row].$1 + 1,
        });
        expect(
          (raw['x']! as int) + (raw['width']! as int),
          lessThanOrEqualTo(1254),
        );
        expect(
          (raw['y']! as int) + (raw['height']! as int),
          lessThanOrEqualTo(1254),
        );
        for (final field in const <String>[
          'rawCropRgbaSha256',
          'sampledCropRgbaSha256',
          'normalizedRgbaSha256',
          'normalizedPngSha256',
        ]) {
          expect(crop[field], matches(RegExp(r'^[0-9a-f]{64}$')));
        }
      }
    }
  });

  test('box-average channels use deterministic integer half-up rounding', () {
    final resampling = (provenance['resampling']! as Map)
        .cast<String, Object?>();
    expect(resampling['algorithm'], 'integer box average');
    expect(resampling['channelRounding'], 'integer-half-up');

    final generatorSource = File(
      'bin/make_alpha_atlas.dart',
    ).readAsStringSync();
    expect(generatorSource, contains('(red + count ~/ 2) ~/ count'));
    expect(generatorSource, contains('(green + count ~/ 2) ~/ count'));
    expect(generatorSource, contains('(blue + count ~/ 2) ~/ count'));
    expect(generatorSource, isNot(contains("'floor(sum / sampleCount)'")));
  });

  test('masters are exactly indices 0 through 35 and match atlas tiles', () {
    final files =
        Directory(_mastersPath)
            .listSync()
            .whereType<File>()
            .map((file) => file.uri.pathSegments.last)
            .toList()
          ..sort();
    expect(files, _masterNames);

    expect((atlas.width, atlas.height), (256, 256));
    expect(atlas.numChannels, 4);
    for (var index = 0; index < _masterNames.length; index++) {
      final master = _decode('$_mastersPath/${_masterNames[index]}');
      expect((master.width, master.height), (16, 16), reason: 'master $index');
      expect(master.numChannels, 4, reason: 'master $index');
      final originX = (index & 15) * 16;
      final originY = (index >> 4) * 16;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          expect(
            _rgba(master.getPixel(x, y)),
            _rgba(atlas.getPixel(originX + x, originY + y)),
            reason: 'master $index pixel ($x,$y)',
          );
        }
      }
    }
  });

  test('unused tile slots 36 through 255 are transparent zero RGBA', () {
    for (var index = 36; index < 256; index++) {
      final originX = (index & 15) * 16;
      final originY = (index >> 4) * 16;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          expect(
            _rgba(atlas.getPixel(originX + x, originY + y)),
            (0, 0, 0, 0),
            reason: 'unused tile $index pixel ($x,$y)',
          );
        }
      }
    }
  });

  test('alpha categories and transparent RGB bleed are exact', () {
    const cutouts = <int>{8, 16, 19, 20, 21, 22, 27};
    for (var index = 0; index < 36; index++) {
      final master = _decode('$_mastersPath/${_masterNames[index]}');
      final alphas = <int>{};
      for (final pixel in master) {
        final alpha = pixel.a.toInt();
        alphas.add(alpha);
        if (cutouts.contains(index) && alpha == 0) {
          expect(
            pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt(),
            greaterThan(0),
            reason:
                'master $index must retain nearest opaque RGB under alpha 0',
          );
        }
      }
      if (index == 9) {
        expect(alphas, const <int>{180});
      } else if (index == 23) {
        expect(alphas, const <int>{230});
      } else if (cutouts.contains(index)) {
        expect(alphas, const <int>{0, 255});
      } else {
        expect(alphas, const <int>{255});
      }
    }
  });

  test('glass is an original open binary mask using only accepted palette', () {
    final glass = _decode('$_mastersPath/16-glass.png');
    final borderAlphas = <int>[];
    for (var coordinate = 0; coordinate < 16; coordinate++) {
      borderAlphas
        ..add(glass.getPixel(coordinate, 0).a.toInt())
        ..add(glass.getPixel(coordinate, 15).a.toInt())
        ..add(glass.getPixel(0, coordinate).a.toInt())
        ..add(glass.getPixel(15, coordinate).a.toInt());
    }
    expect(
      borderAlphas,
      contains(0),
      reason: 'glass must not be an opaque frame',
    );
    expect(borderAlphas, isNot(everyElement(255)));

    final crops = (provenance['crops']! as List).cast<Map<String, Object?>>();
    final glassReference = crops.singleWhere((crop) => crop['id'] == 'r3c1');
    final masterRecord = (provenance['masters']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((master) => master['index'] == 16);
    expect(glassReference['acceptedTileIndex'], isNull);
    expect(
      masterRecord['sha256'],
      isNot(glassReference['normalizedPngSha256']),
    );
    final derivations = (provenance['derivations']! as Map)
        .cast<String, Object?>();
    final glassDerivation = (derivations['16']! as Map).cast<String, Object?>();
    expect(
      ((glassDerivation['spec']! as Map).cast<String, Object?>())['algorithm'],
      'original-open-diagonal-glass-cutout-v1',
    );
  });

  test('directional face and upright image rules remain intact', () {
    expect(blockDefs[Blocks.grass]!.tiles, <int>[
      Tiles.grassSide,
      Tiles.grassSide,
      Tiles.grassTop,
      Tiles.dirt,
      Tiles.grassSide,
      Tiles.grassSide,
    ]);
    expect(blockDefs[Blocks.logOak]!.tiles, <int>[
      Tiles.logSide,
      Tiles.logSide,
      Tiles.logTop,
      Tiles.logTop,
      Tiles.logSide,
      Tiles.logSide,
    ]);
    expect(blockDefs[Blocks.tnt]!.tiles[Face.posY], Tiles.tntTop);
    expect(blockDefs[Blocks.tnt]!.tiles[Face.negY], Tiles.tntBottom);
    expect(blockDefs[Blocks.tnt]!.tiles[Face.posX], Tiles.tntSide);

    final grassSide = _decode('$_mastersPath/03-grass-side.png');
    final topGreenBias = _averageChannelBias(grassSide, 0, 4);
    final bottomGreenBias = _averageChannelBias(grassSide, 8, 8);
    expect(topGreenBias, greaterThan(bottomGreenBias + 35));

    final tntSide = _decode('$_mastersPath/24-tnt-side.png');
    final bestBand = _bestNeutralBand(tntSide);
    expect(bestBand, inInclusiveRange(3, 9));
    for (var y = bestBand; y < bestBand + 4; y++) {
      for (var x = 0; x < 16; x++) {
        final pixel = tntSide.getPixel(x, y);
        expect(
          pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt(),
          greaterThan(360),
          reason: 'the accepted TNT band must have no retained dark glyph/text',
        );
      }
    }
    expect(
      File('$_mastersPath/25-tnt-top.png').readAsBytesSync(),
      isNot(File('$_mastersPath/26-tnt-bottom.png').readAsBytesSync()),
    );
  });

  test(
    'Tiles and BlockDefs use exactly the 0 through 35 face-index contract',
    () {
      const tileConstants = <int>[
        Tiles.stone,
        Tiles.dirt,
        Tiles.grassTop,
        Tiles.grassSide,
        Tiles.sand,
        Tiles.gravel,
        Tiles.logSide,
        Tiles.logTop,
        Tiles.leaves,
        Tiles.water,
        Tiles.bedrock,
        Tiles.oreCoal,
        Tiles.oreIron,
        Tiles.oreGold,
        Tiles.planks,
        Tiles.cobblestone,
        Tiles.glass,
        Tiles.brick,
        Tiles.sponge,
        Tiles.flowerDandelion,
        Tiles.flowerRose,
        Tiles.mushroomBrown,
        Tiles.mushroomRed,
        Tiles.lava,
        Tiles.tntSide,
        Tiles.tntTop,
        Tiles.tntBottom,
        Tiles.sapling,
        Tiles.goldBlock,
        Tiles.ironBlock,
        Tiles.clothWhite,
        Tiles.clothRed,
        Tiles.clothOrange,
        Tiles.clothYellow,
        Tiles.clothLime,
        Tiles.clothBlue,
      ];
      expect(tileConstants, List<int>.generate(36, (index) => index));
      final referenced = <int>{};
      for (final definition in blockDefs.whereType<BlockDef>()) {
        expect(definition.tiles, hasLength(6));
        for (final tile in definition.tiles) {
          expect(tile, inInclusiveRange(0, 35));
          referenced.add(tile);
        }
      }
      expect(referenced, tileConstants.toSet());
    },
  );

  test('mesher retains the 0.5/256 UV inset and upright V mapping', () {
    final source = File(
      '../packages/core/lib/src/mesh/chunk_mesher.dart',
    ).readAsStringSync();
    expect(source, contains('const double _atlasInset = 0.5 / 256;'));
    expect(source, contains('final u0 = tileX / 16 + _atlasInset;'));
    expect(source, contains('final v0 = tileY / 16 + _atlasInset;'));
    expect(source, contains('final u1 = (tileX + 1) / 16 - _atlasInset;'));
    expect(source, contains('final v1 = (tileY + 1) / 16 - _atlasInset;'));
    expect(source, contains('uvCorner < 2 ? v1 : v0'));
  });

  test('provenance is sorted, timestamp-free, and all hashes verify', () {
    _expectSortedJson(provenance);
    final raw = File(_provenancePath).readAsStringSync();
    expect(raw, isNot(contains('timestamp')));
    expect(raw, isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T'))));

    final masters = (provenance['masters']! as List)
        .cast<Map<String, Object?>>();
    expect(masters, hasLength(36));
    for (var index = 0; index < masters.length; index++) {
      final record = masters[index];
      expect(record['index'], index);
      final path = record['path']! as String;
      expect(sha256Hex(File(path).readAsBytesSync()), record['sha256']);
      expect(record['rgbaSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        record['derivationSpecSha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    }

    final output = (provenance['output']! as Map).cast<String, Object?>();
    expect(output['firstUnusedTile'], 36);
    expect(output['sha256'], sha256Hex(File(_atlasPath).readAsBytesSync()));
    expect(output['rgbaSha256'], sha256Hex(_imageRgba(atlas)));

    final generator = (provenance['generator']! as Map).cast<String, Object?>();
    expect(
      generator['sha256'],
      sha256Hex(File(generator['path']! as String).readAsBytesSync()),
    );

    final derivations = (provenance['derivations']! as Map)
        .cast<String, Object?>();
    expect(
      derivations.keys.toList(),
      List<String>.generate(36, (index) => index.toString().padLeft(2, '0')),
    );
    for (final record in derivations.values) {
      final map = (record as Map).cast<String, Object?>();
      expect(map['specSha256'], sha256Hex(_canonicalJsonBytes(map['spec'])));
    }
  });

  test('immutable legacy generator and atlas hashes are unchanged', () {
    expect(
      sha256Hex(File('bin/make_atlas.dart').readAsBytesSync()),
      _legacyGeneratorSha256,
    );
    expect(
      sha256Hex(File('assets/textures/atlas.png').readAsBytesSync()),
      _legacyAtlasSha256,
    );
  });
}

Future<void> _runGenerator() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final dartExecutable = flutterRoot == null
      ? Platform.resolvedExecutable
      : '$flutterRoot/bin/cache/dart-sdk/bin/dart';
  final result = await Process.run(dartExecutable, const <String>[
    'run',
    'bin/make_alpha_atlas.dart',
  ], workingDirectory: Directory.current.path);
  expect(
    result.exitCode,
    0,
    reason: 'generator stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
}

Map<String, String> _generatedHashes() {
  final paths = <String>[
    _atlasPath,
    _provenancePath,
    _referencePath,
    ..._masterNames.map((name) => '$_mastersPath/$name'),
  ]..sort();
  return <String, String>{
    for (final path in paths) path: sha256Hex(File(path).readAsBytesSync()),
  };
}

Image _decode(String path) {
  final decoded = decodePng(File(path).readAsBytesSync());
  expect(decoded, isNotNull, reason: '$path must decode as PNG');
  return decoded!;
}

(int, int, int, int) _rgba(Pixel pixel) =>
    (pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), pixel.a.toInt());

List<int> _imageRgba(Image image) {
  final bytes = <int>[];
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      bytes
        ..add(pixel.r.toInt())
        ..add(pixel.g.toInt())
        ..add(pixel.b.toInt())
        ..add(pixel.a.toInt());
    }
  }
  return bytes;
}

double _averageChannelBias(Image image, int startY, int height) {
  var total = 0;
  var count = 0;
  for (var y = startY; y < startY + height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      total += pixel.g.toInt() - pixel.r.toInt();
      count++;
    }
  }
  return total / count;
}

int _bestNeutralBand(Image image) {
  var bestStart = 3;
  var bestScore = -0x7fffffff;
  for (var start = 3; start <= 9; start++) {
    var score = 0;
    for (var y = start; y < start + 4; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        score += pixel.g.toInt() + pixel.b.toInt() - pixel.r.toInt();
      }
    }
    if (score > bestScore) {
      bestScore = score;
      bestStart = start;
    }
  }
  return bestStart;
}

void _expectSortedJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList();
    final sorted = List<String>.from(keys)..sort();
    expect(keys, sorted);
    for (final child in value.values) {
      _expectSortedJson(child);
    }
  } else if (value is List) {
    for (final child in value) {
      _expectSortedJson(child);
    }
  }
}

List<int> _canonicalJsonBytes(Object? value) =>
    utf8.encode(jsonEncode(_sortJson(value)));

Object? _sortJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortJson(value[key]),
    };
  }
  if (value is List) return value.map(_sortJson).toList();
  return value;
}
