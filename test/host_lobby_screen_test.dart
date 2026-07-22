import 'package:armor_up/screens/host_lobby_screen.dart';
import 'package:armor_up/state/app_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows name entry fields and a Create lobby button', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).enterHostSetup();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostLobbyScreen()),
      ),
    );

    expect(find.text('YOUR NAME'), findsOneWidget);
    expect(find.text('GAME NAME'), findsOneWidget);
    expect(find.text('CREATE LOBBY'), findsOneWidget);
  });

  testWidgets('tapping Back returns to mode-select', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).enterHostSetup();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostLobbyScreen()),
      ),
    );

    await tester.tap(find.text('BACK'));
    await tester.pump();

    expect(container.read(appModeControllerProvider).mode, AppMode.modeSelect);
  });
}
