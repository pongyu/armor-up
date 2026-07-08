import 'package:armor_up/screens/host_disconnected_screen.dart';
import 'package:armor_up/state/app_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the disconnect reason and a way back to mode-select', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).hostDisconnected('A player disconnected.');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostDisconnectedScreen()),
      ),
    );

    expect(find.text('A player disconnected.'), findsOneWidget);
    expect(find.text('Back to start'), findsOneWidget);
  });

  testWidgets('tapping "Back to start" returns to mode-select', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).hostDisconnected('The host ended the game.');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostDisconnectedScreen()),
      ),
    );

    await tester.tap(find.text('Back to start'));
    await tester.pump();

    expect(container.read(appModeControllerProvider).mode, AppMode.modeSelect);
  });
}
