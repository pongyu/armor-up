import 'dart:ui';

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

  testWidgets('hand cards with a Discard button do not overflow on a phone-sized screen',
      (WidgetTester tester) async {
    // Reproduces a real Pixel device viewport (smaller than the default test
    // surface), where the Discard TextButton's default 48dp tap target
    // pushed _HandCard's Column past its allotted height.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ArmorUpApp()));

    await tester.tap(find.text('Start Game'));
    await tester.pump();
    await tester.tap(find.text("I'm ready"));
    await tester.pump();

    await tester.tap(find.text('Draw'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
