import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armor_up/main.dart';

void main() {
  testWidgets('app starts on the setup screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ArmorUpApp()));

    expect(find.text('Suit up'), findsOneWidget);
    expect(find.text('Start Game'), findsOneWidget);
  });

  testWidgets('starting a game navigates to the pass-device screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ArmorUpApp()));

    await tester.tap(find.text('Start Game'));
    await tester.pump();

    expect(find.text('Pass the device to'), findsOneWidget);
  });
}
