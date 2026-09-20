import 'package:flutter_test/flutter_test.dart';

import 'package:wuarikes_app/main.dart';

void main() {
  testWidgets('WuarikesApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const WuarikesApp());
    expect(find.byType(WuarikesApp), findsOneWidget);
  });
}
