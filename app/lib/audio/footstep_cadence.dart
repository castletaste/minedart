/// Distance-based footstep timing matching the simple cadence of early
/// Minecraft, where a step is emitted after roughly 1.67 travelled blocks.
final class FootstepCadence {
  FootstepCadence({this.strideBlocks = classicStrideBlocks})
    : assert(strideBlocks > 0 && strideBlocks.isFinite);

  static const double classicStrideBlocks = 5 / 3;

  final double strideBlocks;
  double _groundedDistance = 0;

  /// Records actual horizontal displacement and returns whether one footstep
  /// should play this frame. Extra crossings from a stalled frame are folded
  /// into the remainder so audio cannot burst after a hitch.
  bool update({required double horizontalDistance, required bool grounded}) {
    if (!grounded) {
      reset();
      return false;
    }
    if (!horizontalDistance.isFinite || horizontalDistance <= 0) return false;

    _groundedDistance += horizontalDistance;
    if (_groundedDistance + 1e-9 < strideBlocks) return false;
    _groundedDistance %= strideBlocks;
    return true;
  }

  void reset() {
    _groundedDistance = 0;
  }
}
