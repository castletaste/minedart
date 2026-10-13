import 'package:flutter/material.dart';

import '../../diagnostics/diagnostics_snapshot.dart';

/// Compact developer-only health view embedded in the F3 overlay.
final class DeveloperHealthPanel extends StatelessWidget {
  const DeveloperHealthPanel({required this.snapshot, super.key});

  final DiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Text(
    formatDeveloperHealth(snapshot),
    style: const TextStyle(
      fontSize: 10,
      height: 1.3,
      color: Color(0xFFFFE5A3),
      fontFamily: 'monospace',
    ),
  );
}

String formatDeveloperHealth(DiagnosticsSnapshot snapshot) {
  final health = snapshot.health.name.toUpperCase();
  final issues = snapshot.issues;
  return 'health $health  epoch ${snapshot.sessionEpoch}\n'
      'input ${snapshot.inputActive ? 'active' : 'idle'}  '
      'renderer ${snapshot.rendererReady ? 'ready' : 'pending'}  '
      'storage ${snapshot.storageReady ? 'ready' : 'error'}\n'
      'active chunks ${snapshot.activeChunks}  mesh queue ${snapshot.meshQueue}\n'
      'retained ${snapshot.retainedComponents} comps / '
      '${snapshot.retainedMeshBytes} bytes\n'
      'issues ${issues.isEmpty ? '-' : issues.join(', ')}';
}
