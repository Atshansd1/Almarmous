import 'package:flutter_test/flutter_test.dart';

import 'package:almarmous_orders/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('parses iFast label OCR without using template labels as values', () {
    final parsed = LabelParser.parse('''
iFast
Quick as a click
XR873442
5526311222 رقم موبايل المستلم Recipient Phone
شارع الحميدية المنطقة Area
عجمان المدينة City
اجمالي الاستلام Total COD
250
Package Price
Delivery Fees
Count Of Parts
600 500 555
''');

    expect(parsed.trackingNumber, 'XR873442');
    expect(parsed.phone, '5526311222');
    expect(parsed.city, 'عجمان');
    expect(parsed.area, 'شارع الحميدية');
    expect(parsed.cod, 250);
  });

  test('does not use tracking digits as COD when amount is missing', () {
    final parsed = LabelParser.parse('''
XR873442
Recipient Phone
Package Price
Count Of Parts
600 500 555
''');

    expect(parsed.trackingNumber, 'XR873442');
    expect(parsed.city, isEmpty);
    expect(parsed.area, isEmpty);
    expect(parsed.cod, 0);
  });

  test('parses Arabic handwritten location from Cloud Vision OCR', () {
    final parsed = LabelParser.parse('''
iFast
Quick as a clicki
5506311222
XR873442
رقم موبايل المستلم
Recipient Phone
المدينة
City
عدد الأجزاء
عجمان المية شارع الإعلام
Count Of Parts
Area
قيمة الشحنة
رسوم التوصيل
Package Price
Delivery Fees
اجمالي الاستلام
Total COD
250
( 600500555
''');

    expect(parsed.trackingNumber, 'XR873442');
    expect(parsed.phone, '5506311222');
    expect(parsed.city, 'عجمان');
    expect(parsed.area, 'المية شارع الإعلام');
    expect(parsed.cod, 250);
  });

  test('parses Abu Dhabi handwritten Arabic before printed labels', () {
    final parsed = LabelParser.parse('''
XR873444
503322759 رقم موبايل المستلم
المدينة City
أبوظبي الشوامخ
المنطقة Area
اجمالي الاستلام Total COD
250
''');

    expect(parsed.trackingNumber, 'XR873444');
    expect(parsed.phone, '503322759');
    expect(parsed.city, 'أبوظبي');
    expect(parsed.area, 'الشوامخ');
    expect(parsed.cod, 250);
  });

  testWidgets('shows Almarmous dashboard', (WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(const AlmarmousApp());
    await tester.pumpAndSettle();

    expect(find.text('المرموس'), findsOneWidget);
  });
}
