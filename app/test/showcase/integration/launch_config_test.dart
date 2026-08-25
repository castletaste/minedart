import 'dart:math';

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
    expect(config.seedWasSpecified, isTrue);

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
    expect(
      ShowcaseLaunchConfig.fromUri(
        Uri.parse('https://example.test/?preset=islands'),
      ).seedWasSpecified,
      isFalse,
    );
  });

  test('missing seeds resolve lazily while explicit seeds stay exact', () {
    var calls = 0;
    int generated() {
      calls++;
      return -123;
    }

    final implicit = ShowcaseLaunchConfig.fromUri(
      Uri.parse('https://example.test/?preset=islands'),
    );
    expect(implicit.resolveNewWorldSeed(generate: generated), -123);
    expect(calls, 1);

    final explicit = ShowcaseLaunchConfig.fromUri(
      Uri.parse('https://example.test/?seed=42&preset=islands'),
    );
    expect(explicit.resolveNewWorldSeed(generate: generated), 42);
    expect(resolveOptionalWorldSeed(7, generate: generated), 7);
    expect(calls, 1, reason: 'explicit seeds must not consume entropy');
  });

  test('random world seeds cover the signed 32-bit contract', () {
    final random = Random(0x5eed);
    final first = generateRandomWorldSeed(random);
    final second = generateRandomWorldSeed(random);

    expect(first, inInclusiveRange(-0x80000000, 0x7FFFFFFF));
    expect(second, inInclusiveRange(-0x80000000, 0x7FFFFFFF));
    expect(second, isNot(first));
  });

  test('platform entropy resolves a valid seed', () {
    expect(
      generateRandomWorldSeed(),
      inInclusiveRange(-0x80000000, 0x7FFFFFFF),
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
