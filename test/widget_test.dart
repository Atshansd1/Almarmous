import 'package:flutter_test/flutter_test.dart';

import 'package:almarmous_orders/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('shows Almarmous dashboard', (WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(const AlmarmousApp());
    await tester.pumpAndSettle();

    expect(find.text('المرموس'), findsOneWidget);
  });
}
