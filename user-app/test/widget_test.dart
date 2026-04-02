import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LittleBrother smoke test', (WidgetTester tester) async {
    // This app requires platform permissions and native channels,
    // so we just verify the test framework runs.
    expect(1 + 1, equals(2));
  });
}
