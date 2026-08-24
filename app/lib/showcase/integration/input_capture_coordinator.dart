/// Reference-counted ownership for overlapping modal route transitions.
final class InputCaptureCoordinator {
  InputCaptureCoordinator(this.onChanged);

  final void Function(bool captured) onChanged;
  int _owners = 0;

  int get owners => _owners;
  bool get isCaptured => _owners > 0;

  void update(bool acquired) {
    final wasCaptured = isCaptured;
    _owners = acquired ? _owners + 1 : (_owners - 1).clamp(0, 1 << 20);
    if (wasCaptured != isCaptured) onChanged(isCaptured);
  }
}
