import 'package:armor_up/screens/waiting_for_host_screen.dart';
import 'package:armor_up/state/app_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net/net.dart';

Future<void> _waitUntil(bool Function() predicate) async {
  while (!predicate()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets('shows the live roster while waiting for the host to start', (tester) async {
    // Real socket I/O (HostServer/GameClient) needs the real event loop,
    // which testWidgets' fake-async zone does not drive on its own -
    // tester.runAsync() steps outside that zone for the calls that need
    // real async completion.
    final host = HostServer(hostDisplayName: 'Mumu');
    late int port;
    final hostClient = GameClient();
    addTearDown(hostClient.close);
    final joinerClient = GameClient();
    addTearDown(joinerClient.close);
    addTearDown(host.stop);

    await tester.runAsync(() async {
      port = await host.start();
      await hostClient.connectToLobby('127.0.0.1', port, 'Mumu');
      await joinerClient.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).enterWaitingForHost(joinerClient);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WaitingForHostScreen()),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('Mumu'), findsOneWidget);
    expect(find.text('Zoe'), findsOneWidget);
    expect(find.text('Waiting for the host to start the game...'), findsOneWidget);
  });

  testWidgets('tapping Cancel returns to mode-select', (tester) async {
    final host = HostServer(hostDisplayName: 'Mumu');
    late int port;
    final joinerClient = GameClient();
    addTearDown(joinerClient.close);
    addTearDown(host.stop);

    await tester.runAsync(() async {
      port = await host.start();
      await joinerClient.connectToLobby('127.0.0.1', port, 'Zoe');
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appModeControllerProvider.notifier).enterWaitingForHost(joinerClient);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WaitingForHostScreen()),
      ),
    );
    await tester.pump();

    // The Cancel button's onPressed calls returnToModeSelect() directly
    // without awaiting it (Flutter buttons discard the callback's
    // returned Future), so tap() itself returns before the real socket
    // close()/stop() calls inside it finish. Poll for the mode change
    // inside runAsync so the real event loop actually drives that async
    // work to completion before the test (and its addTearDown container
    // disposal) proceeds.
    await tester.runAsync(() async {
      await tester.tap(find.text('Cancel'));
      await _waitUntil(
        () => container.read(appModeControllerProvider).mode == AppMode.modeSelect,
      );
    });
    await tester.pump();

    expect(container.read(appModeControllerProvider).mode, AppMode.modeSelect);
  });
}
