import 'package:web/web.dart' as web;

/// Initial web control mode. A real touch event may still enable hybrid input.
bool get prefersTouchControls =>
    web.window.matchMedia('(pointer: coarse)').matches;
