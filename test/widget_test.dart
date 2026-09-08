import 'package:flutter_test/flutter_test.dart';
import 'package:zen_launcher/main.dart';

void main() {
  testWidgets('ZenLauncherApp smoke test builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ZenLauncherApp());
    await tester.pump();

    // Verify ZenLauncherApp component loads
    expect(find.byType(ZenLauncherApp), findsOneWidget);
  });
}
