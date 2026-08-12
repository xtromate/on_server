// Basic smoke test: the app boots to the connection-settings screen when
// no host/token has been configured yet.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:on_server/main.dart';

void main() {
  testWidgets('Boots to the connection settings screen when unconfigured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OnServerApp());
    await tester.pumpAndSettle();

    expect(find.text('Connect to your phone'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
  });
}
