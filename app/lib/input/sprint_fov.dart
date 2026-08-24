import 'dart:math' as math;

const double basePlayerFov = 70;
const double sprintPlayerFov = 75;
const double _sprintFovResponse = 12;

/// Allocation-free exponential easing for the sprint camera cue.
double stepSprintFov({
  required double current,
  required bool sprinting,
  required bool reducedMotion,
  required double dt,
}) {
  if (reducedMotion) return basePlayerFov;
  if (!current.isFinite) current = basePlayerFov;
  final target = sprinting ? sprintPlayerFov : basePlayerFov;
  if (!dt.isFinite || dt <= 0) return current;
  final alpha = 1 - math.exp(-_sprintFovResponse * dt.clamp(0, 0.1));
  final next = current + (target - current) * alpha;
  return (target - next).abs() < 0.001 ? target : next;
}
