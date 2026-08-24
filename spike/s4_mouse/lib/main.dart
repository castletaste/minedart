import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(const MouseLookApp());

class MouseLookApp extends StatelessWidget {
  const MouseLookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MineDart S4 Mouse Capture',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff70d6a4),
          brightness: Brightness.dark,
        ),
      ),
      home: const MouseLookScreen(),
    );
  }
}

class MouseLookScreen extends StatefulWidget {
  const MouseLookScreen({super.key});

  @override
  State<MouseLookScreen> createState() => _MouseLookScreenState();
}

class _MouseLookScreenState extends State<MouseLookScreen> {
  static const _methods = MethodChannel('minedart/mouse');
  static const _events = EventChannel('minedart/mouse/events');
  static const _sensitivity = 0.004;

  final _keyboardFocus = FocusNode(debugLabel: 'mouse-look-keyboard');
  StreamSubscription<Object?>? _eventSubscription;

  bool _captured = false;
  bool _frameScheduled = false;
  String _status = 'Нажмите Capture, затем двигайте мышью';
  double _yaw = 0;
  double _pitch = 0;
  double _pendingDx = 0;
  double _pendingDy = 0;
  double _lastDx = 0;
  double _lastDy = 0;
  int _eventCount = 0;
  int _frameCount = 0;
  DateTime? _firstEventAt;

  @override
  void initState() {
    super.initState();
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _status = 'EventChannel error: $error');
      },
    );
  }

  void _handleNativeEvent(Object? event) {
    if (event is! Map) return;
    final type = event['type'];
    if (type == 'delta') {
      final dx = (event['dx'] as num?)?.toDouble() ?? 0;
      final dy = (event['dy'] as num?)?.toDouble() ?? 0;
      _pendingDx += dx;
      _pendingDy += dy;
      _eventCount++;
      _firstEventAt ??= DateTime.now();
      _scheduleVisualUpdate();
    } else if (type == 'capture') {
      final captured = event['captured'] == true;
      final reason = event['reason'] as String?;
      if (!mounted) return;
      setState(() {
        _captured = captured;
        _status = captured
            ? 'Захват активен — Esc отпускает'
            : 'Захват отпущен${reason == null ? '' : ' ($reason)'}';
      });
    }
  }

  void _scheduleVisualUpdate() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted) return;
      final dx = _pendingDx;
      final dy = _pendingDy;
      _pendingDx = 0;
      _pendingDy = 0;
      setState(() {
        _lastDx = dx;
        _lastDy = dy;
        _yaw = (_yaw + dx * _sensitivity) % (math.pi * 2);
        _pitch = (_pitch + dy * _sensitivity).clamp(
          -math.pi / 2 + 0.05,
          math.pi / 2 - 0.05,
        );
        _frameCount++;
      });
    });
  }

  Future<void> _capture() async {
    _keyboardFocus.requestFocus();
    try {
      final result = await _methods.invokeMapMethod<String, Object?>('capture');
      if (!mounted) return;
      setState(() {
        _captured = result?['captured'] == true;
        _status = result?['alreadyCaptured'] == true
            ? 'Захват уже был активен'
            : 'Захват активен — Esc отпускает';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '${error.code}: ${error.message}');
    }
  }

  Future<void> _release() async {
    try {
      await _methods.invokeMethod<void>('release');
      if (!mounted) return;
      setState(() {
        _captured = false;
        _status = 'Захват отпущен';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '${error.code}: ${error.message}');
    }
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_release());
    }
  }

  double get _eventsPerSecond {
    final first = _firstEventAt;
    if (first == null) return 0;
    final seconds = DateTime.now().difference(first).inMilliseconds / 1000;
    return seconds <= 0 ? 0 : _eventCount / seconds;
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _keyboardFocus.dispose();
    if (_captured) unawaited(_methods.invokeMethod<void>('release'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'S4 · macOS mouse look',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(_status),
                const SizedBox(height: 20),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xff101713),
                      border: Border.all(
                        color: _captured
                            ? const Color(0xff70d6a4)
                            : Colors.white24,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: CustomPaint(
                      painter: LookPainter(yaw: _yaw, pitch: _pitch),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    Text(
                      'delta: ${_lastDx.toStringAsFixed(1)}, ${_lastDy.toStringAsFixed(1)}',
                    ),
                    Text('yaw: ${(_yaw * 180 / math.pi).toStringAsFixed(1)}°'),
                    Text(
                      'pitch: ${(_pitch * 180 / math.pi).toStringAsFixed(1)}°',
                    ),
                    Text('events: $_eventCount'),
                    Text(
                      'events/s avg: ${_eventsPerSecond.toStringAsFixed(1)}',
                    ),
                    Text('visual frames: $_frameCount'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _capture,
                        icon: const Icon(Icons.mouse),
                        label: const Text('Capture mouse'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _captured ? _release : null,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Release (Esc)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LookPainter extends CustomPainter {
  const LookPainter({required this.yaw, required this.pitch});

  final double yaw;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = math.min(size.width, size.height) * 0.23;
    final vertices = <({double x, double y, double z})>[
      for (final z in [-1.0, 1.0])
        for (final y in [-1.0, 1.0])
          for (final x in [-1.0, 1.0]) (x: x, y: y, z: z),
    ];
    final projected = vertices.map((point) {
      final x1 = point.x * math.cos(yaw) - point.z * math.sin(yaw);
      final z1 = point.x * math.sin(yaw) + point.z * math.cos(yaw);
      final y2 = point.y * math.cos(pitch) - z1 * math.sin(pitch);
      final z2 = point.y * math.sin(pitch) + z1 * math.cos(pitch);
      final perspective = 3.5 / (4.5 + z2);
      return center + Offset(x1, y2) * scale * perspective;
    }).toList();
    final paint = Paint()
      ..color = const Color(0xff70d6a4)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const edges = <(int, int)>[
      (0, 1),
      (0, 2),
      (0, 4),
      (1, 3),
      (1, 5),
      (2, 3),
      (2, 6),
      (3, 7),
      (4, 5),
      (4, 6),
      (5, 7),
      (6, 7),
    ];
    for (final (a, b) in edges) {
      canvas.drawLine(projected[a], projected[b], paint);
    }
    canvas.drawCircle(center, 4, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(LookPainter oldDelegate) =>
      yaw != oldDelegate.yaw || pitch != oldDelegate.pitch;
}
