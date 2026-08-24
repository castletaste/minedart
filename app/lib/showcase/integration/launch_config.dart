/// Typed, side-effect-free parsing for Minedart share/deep links.
library;

const int kDefaultWorldSeed = 0x5eed;

enum LaunchWorldPreset { classic, flat, islands }

final class ShowcaseLaunchConfig {
  const ShowcaseLaunchConfig({
    required this.seed,
    required this.preset,
    this.worldId,
    this.requestsGeneratedWorld = false,
  });

  factory ShowcaseLaunchConfig.fromUri(Uri uri) {
    final query = uri.queryParameters;
    return ShowcaseLaunchConfig(
      seed: parseWorldSeed(query['seed']),
      preset: LaunchWorldPreset.values.firstWhere(
        (value) => value.name == query['preset'],
        orElse: () => LaunchWorldPreset.classic,
      ),
      worldId: _cleanWorldId(query['world']),
      requestsGeneratedWorld:
          query.containsKey('seed') || query.containsKey('preset'),
    );
  }

  final int seed;
  final LaunchWorldPreset preset;
  final String? worldId;
  final bool requestsGeneratedWorld;

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
