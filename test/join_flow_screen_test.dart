import 'package:armor_up/screens/join_flow_screen.dart';
import 'package:armor_up/state/app_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows name entry, manual-connect fields, and discovery placeholder',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).enterJoinFlow();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: JoinFlowScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('ip:port'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    // mDNS discovery has no platform channel handler in a widget test, so
    // it never reports any games - the "Searching..." placeholder should
    // still render rather than crash the screen.
    expect(find.text('Searching...'), findsOneWidget);
  });

  testWidgets('manual entry rejects malformed address input', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).enterJoinFlow();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: JoinFlowScreen()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'ip:port'), 'not-an-address');
    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(find.text('Enter address as ip:port'), findsOneWidget);
  });

  testWidgets('tapping Back returns to mode-select', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).enterJoinFlow();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: JoinFlowScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Back'));
    await tester.pump();

    expect(container.read(appModeControllerProvider).mode, AppMode.modeSelect);
  });
}
