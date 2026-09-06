import 'package:flutter/material.dart';

import '../../audio/audio.dart';
import '../../data/worlds/world_repository.dart';
import '../controller/options_controller.dart';
import 'game_shell.dart';
import 'world_runtime.dart';

export 'world_defaults.dart' show defaultWorldSpawn, importedWorldName;

/// The app observes only accessibility options that actually affect its theme.
final class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({
    required this.repository,
    required this.audio,
    required this.initialRuntime,
    super.key,
  });
  final WorldRepository repository;
  final AudioServiceApi audio;
  final WorldRuntime initialRuntime;

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

final class _ShowcaseAppState extends State<ShowcaseApp> {
  final _options = OptionsController();
  final _accessibility = ValueNotifier((
    highContrast: false,
    reducedMotion: false,
  ));

  @override
  void initState() {
    super.initState();
    _options.addListener(_updateAccessibility);
  }

  void _updateAccessibility() {
    _accessibility.value = (
      highContrast: _options.highContrast,
      reducedMotion: _options.reducedMotion,
    );
  }

  @override
  void dispose() {
    _options
      ..removeListener(_updateAccessibility)
      ..dispose();
    _accessibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _accessibility,
    child: GameShell(
      repository: widget.repository,
      audio: widget.audio,
      initialRuntime: widget.initialRuntime,
      options: _options,
    ),
    builder: (context, options, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Minedart Classic Showcase',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B9D42),
          brightness: Brightness.dark,
          contrastLevel: options.highContrast ? 1 : 0,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: options.reducedMotion),
        child: child!,
      ),
      home: child,
    ),
  );
}
