import 'package:flutter_test/flutter_test.dart';
import 'package:minedart/input/sprint_fov.dart';

void main() {
  test('sprint FOV eases toward 75 and returns toward 70', () {
    var fov = basePlayerFov;
    for (var i = 0; i < 30; i++) {
      fov = stepSprintFov(
        current: fov,
        sprinting: true,
        reducedMotion: false,
        dt: 1 / 60,
      );
    }
    expect(fov, greaterThan(74));
    expect(fov, lessThanOrEqualTo(sprintPlayerFov));

    for (var i = 0; i < 30; i++) {
      fov = stepSprintFov(
        current: fov,
        sprinting: false,
        reducedMotion: false,
        dt: 1 / 60,
      );
    }
    expect(fov, lessThan(71));
    expect(fov, greaterThanOrEqualTo(basePlayerFov));
  });

  test('Reduced Motion always snaps to the base FOV', () {
    expect(
      stepSprintFov(
        current: sprintPlayerFov,
        sprinting: true,
        reducedMotion: true,
        dt: 1 / 60,
      ),
      basePlayerFov,
    );
  });

  test('invalid or zero time does not destabilize the camera', () {
    expect(
      stepSprintFov(current: 72, sprinting: true, reducedMotion: false, dt: 0),
      72,
    );
    expect(
      stepSprintFov(
        current: double.nan,
        sprinting: false,
        reducedMotion: false,
        dt: 1 / 60,
      ),
      basePlayerFov,
    );
  });
}
