import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/showcase/integration/input_capture_coordinator.dart';

void main() {
  test('overlapping outgoing and incoming modals keep capture active', () {
    final states = <bool>[];
    final coordinator = InputCaptureCoordinator(states.add);

    coordinator.update(true); // pause route
    coordinator.update(true); // incoming library route mounts
    coordinator.update(false); // outgoing pause route disposes late

    expect(coordinator.owners, 1);
    expect(coordinator.isCaptured, isTrue);
    expect(states, [true]);

    coordinator.update(false);
    coordinator.update(false); // duplicate dispose stays bounded
    expect(coordinator.owners, 0);
    expect(states, [true, false]);
  });
}
