import 'package:flutter_test/flutter_test.dart';
import 'package:amity_icmr_mobile/main.dart';

void main() {
  testWidgets('App smoke test — mounts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const AmityIcmrApp());
    // App should build without throwing — provider is now inside AmityIcmrApp
    expect(find.byType(AmityIcmrApp), findsOneWidget);
  });
}
