/// Typed, side-effect-free parsing for Minedart share/deep links.
library;

import 'dart:math';

const int kDefaultWorldSeed = 0x5eed;

typedef WorldSeedGenerator = int Function();

/// Produces a signed 32-bit seed from the platform cryptographic RNG.
int generateRandomWorldSeed([Random? random]) {
  final value = (random ?? Random.secure()).nextInt(0x100000000);
  return value >= 0x80000000 ? value - 0x100000000 : value;
}

int resolveOptionalWorldSeed(int? seed, {WorldSeedGenerator? generate}) =>
    seed ?? (generate ?? generateRandomWorldSeed)();

enum LaunchWorldPreset { classic, flat, islands }

final class ShowcaseLaunchConfig {
  const ShowcaseLaunchConfig({
    required this.seed,
    required this.preset,
    this.worldId,
    this.requestsGeneratedWorld = false,
    this.seedWasSpecified = true,
  });

  factory ShowcaseLaunchConfig.fromUri(Uri uri) {
    final query = uri.queryParameters;
    final rawSeed = query['seed'];
    return ShowcaseLaunchConfig(
      seed: parseWorldSeed(rawSeed),
      preset: LaunchWorldPreset.values.firstWhere(
        (value) => value.name == query['preset'],
        orElse: () => LaunchWorldPreset.classic,
      ),
      worldId: _cleanWorldId(query['world']),
      requestsGeneratedWorld:
          query.containsKey('seed') || query.containsKey('preset'),
      seedWasSpecified: rawSeed != null && rawSeed.trim().isNotEmpty,
    );
  }

  final int seed;
  final LaunchWorldPreset preset;
  final String? worldId;
  final bool requestsGeneratedWorld;
  final bool seedWasSpecified;

  int resolveNewWorldSeed({WorldSeedGenerator? generate}) => seedWasSpecified
      ? seed
      : resolveOptionalWorldSeed(null, generate: generate);

  Uri shareUri(Uri base) {
    final query = <String, String>{
      'seed': encodeWorldSeed(seed),
      'preset': preset.name,
    };
    return base.replace(queryParameters: query, fragment: '');
  }
}

int parseWorldSeed(String? value) {
  if (value == null || value.trim().isEmpty) return kDefaultWorldSeed;
  final normalized = value.trim().toLowerCase();
  final int? parsed;
  if (normalized.startsWith('-0x')) {
    final magnitude = int.tryParse(normalized.substring(3), radix: 16);
    parsed = magnitude == null ? null : -magnitude;
  } else if (normalized.startsWith('0x')) {
    parsed = int.tryParse(normalized.substring(2), radix: 16);
  } else {
    parsed = int.tryParse(normalized) ?? int.tryParse(normalized, radix: 16);
  }
  return parsed ?? kDefaultWorldSeed;
}

String encodeWorldSeed(int seed) => seed < 0
    ? '-0x${(-seed).toRadixString(16)}'
    : '0x${seed.toRadixString(16)}';

String? _cleanWorldId(String? value) {
  final clean = value?.trim();
  if (clean == null || clean.isEmpty || clean.length > 64) return null;
  return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(clean) ? clean : null;
}
