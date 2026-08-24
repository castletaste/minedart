import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/integration/launch_config.dart';

void main() {
  test('parses decimal and hexadecimal seeds', () {
    expect(parseWorldSeed('123'), 123);
    expect(parseWorldSeed('0x5eed'), 0x5eed);
    expect(parseWorldSeed('-0x10'), -16);
    expect(parseWorldSeed('5eed'), 0x5eed);
    expect(parseWorldSeed('bad seed'), kDefaultWorldSeed);
  });

  test('parses typed launch options and rejects unsafe world ids', () {
    final config = ShowcaseLaunchConfig.fromUri(
      Uri.parse('https://example.test/?seed=42&preset=flat&world=a_b'),
    );
    expect(config.seed, 42);
    expect(config.preset, LaunchWorldPreset.flat);
    expect(config.worldId, 'a_b');
    expect(config.requestsGeneratedWorld, isTrue);

    expect(
      ShowcaseLaunchConfig.fromUri(
        Uri.parse('https://example.test/?world=../../etc'),
      ).worldId,
      isNull,
    );
    expect(
      ShowcaseLaunchConfig.fromUri(
        Uri.parse('https://example.test/'),
      ).requestsGeneratedWorld,
      isFalse,
    );
  });

  test('shareUri emits portable seed and preset only', () {
    final config = ShowcaseLaunchConfig(
      seed: 0x5eed,
      preset: LaunchWorldPreset.classic,
      worldId: 'private-local-id',
    );
    final uri = config.shareUri(Uri.parse('https://example.test/play?old=1'));
    expect(uri.queryParameters['seed'], '0x5eed');
    expect(uri.queryParameters['preset'], 'classic');
    expect(uri.queryParameters.containsKey('world'), isFalse);
    expect(uri.queryParameters.containsKey('builder'), isFalse);
  });

  test('shared seeds round-trip decimal-looking hexadecimal values', () {
    for (final seed in <int>[0, 10, 16, 42, -16, 0x5eed]) {
      final encoded = encodeWorldSeed(seed);
      expect(parseWorldSeed(encoded), seed, reason: encoded);
    }
  });
}
