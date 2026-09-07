import 'package:flutter/foundation.dart';

/// Whether the current native platform normally needs on-screen controls.
bool get prefersTouchControls =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
