import 'package:armor_up/screens/mode_select_screen.dart';
import 'package:armor_up/state/app_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows all three mode choices', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ModeSelectScreen())),
    );

    expect(find.text('Play pass-and-play'), findsOneWidget);
    expect(find.text('Host a LAN game'), findsOneWidget);
    expect(find.text('Join a LAN game'), findsOneWidget);
  });

  testWidgets('choosing pass-and-play sets hotseatSetup mode', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ModeSelectScreen()),
      ),
    );

    await tester.tap(find.text('Play pass-and-play'));
    await tester.pump();

    expect(container.read(appModeControllerProvider).mode, AppMode.hotseatSetup);
  });

  testWidgets('choosing join sets joinFlow mode', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ModeSelectScreen()),
      ),
    );

    await tester.tap(find.text('Join a LAN game'));
    await tester.pump();

    expect(container.read(appModeControllerProvider).mode, AppMode.joinFlow);
  });

  testWidgets('choosing host sets hostSetup mode', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ModeSelectScreen()),
      ),
    );

    await tester.tap(find.text('Host a LAN game'));
    await tester.pump();

    expect(container.read(appModeControllerProvider).mode, AppMode.hostSetup);
  });
}
