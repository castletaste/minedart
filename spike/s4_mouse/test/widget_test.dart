import 'package:flutter_test/flutter_test.dart';
import 'package:s4_mouse/main.dart';

void main() {
  testWidgets('shows mouse capture controls and counters', (tester) async {
    await tester.pumpWidget(const MouseLookApp());

    expect(find.text('S4 · macOS mouse look'), findsOneWidget);
    expect(find.text('Capture mouse'), findsOneWidget);
    expect(find.text('events: 0'), findsOneWidget);
  });
}
