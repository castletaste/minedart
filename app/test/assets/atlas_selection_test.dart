import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';
import 'package:minedart/assets/atlas_selection.dart';

const bool _hasAtlasDefine = bool.hasEnvironment(kMinedartAtlasDefine);

void main() {
  group('atlas selector', () {
    test('defaults to the Alpha-like atlas', () {
      expect(kDefaultMinedartAtlas, 'alpha');
      expect(atlasSelectionFromValue(kDefaultMinedartAtlas), same(kAlphaAtlas));
      expect(kAlphaAtlas.assetPath, 'textures/atlas_alpha.png');
    });

    test('uses and validates the compile-time value', () {
      if (!_hasAtlasDefine) {
        expect(kMinedartAtlasValue, 'alpha');
        expect(selectedAtlas, same(kAlphaAtlas));
      } else if (kMinedartAtlasValue case 'alpha' || 'legacy') {
        expect(
          selectedAtlas,
          same(atlasSelectionFromValue(kMinedartAtlasValue)),
        );
      } else {
        expect(() => selectedAtlas, throwsA(isA<ArgumentError>()));
      }
    });

    test('resolves both supported values without fallback', () {
      expect(atlasSelectionFromValue('alpha'), same(kAlphaAtlas));
      expect(atlasSelectionFromValue('legacy'), same(kLegacyAtlas));
      expect(kLegacyAtlas.assetPath, 'textures/atlas.png');
    });

    test('rejects invalid values clearly', () {
      expect(
        () => atlasSelectionFromValue('future'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains(kMinedartAtlasDefine),
              contains('alpha'),
              contains('legacy'),
              contains('future'),
            ),
          ),
        ),
      );
    });
  });

  for (final selection in <AtlasSelection>[kAlphaAtlas, kLegacyAtlas]) {
    test('${selection.variant.name} asset exists and is 256x256 RGBA', () {
      final file = File('assets/${selection.assetPath}');
      expect(file.existsSync(), isTrue, reason: file.path);
      final image = decodePng(file.readAsBytesSync());
      expect(image, isNotNull, reason: '${file.path} must decode as PNG');
      expect(image!.width, 256);
      expect(image.height, 256);
      expect(image.numChannels, 4);
    });
  }
}
