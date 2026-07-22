import 'package:armor_up/screens/game_screen.dart';
import 'package:armor_up/state/app_mode_controller.dart';
import 'package:armor_up/state/game_controller.dart';
import 'package:armor_up/state/game_providers.dart';
import 'package:armor_up/state/net_game_controller.dart';
import 'package:armor_up/state/turn_actor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';

/// Covers Phase 4: the LAN defense-response countdown (Part 1), spectator
/// waiting states (Part 2), and the shared resolution beat (Part 3) - each
/// exercised against a *real* HostServer + GameClient pair over a loopback
/// socket (same convention as packages/net/test/defense_timeout_test.dart
/// and test/waiting_for_host_screen_test.dart), so this also functions as
/// an end-to-end check that responseDeadlineEpochMs actually survives the
/// GameClient -> NetGameController -> GameUiState -> provider chain added
/// in this phase, not just that the UI renders correctly given a value.
void main() {
  // GameScreen.initState calls WakelockPlus.enable()/.disable(), which
  // goes over a Pigeon-generated platform channel with no test-harness
  // mock registered by default - unmocked, it throws a PlatformException
  // ("Unable to establish connection on channel...") the instant a real
  // async gap (tester.runAsync, used throughout this file for the real
  // HostServer/GameClient socket I/O) lets that awaited Future's error
  // surface. Respond to the channel with an empty success reply so
  // GameScreen behaves as it would on a real device, without needing a
  // fake platform plugin package.
  const wakelockChannel = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
    wakelockChannel,
    (message) async => const StandardMessageCodec().encodeMessage(<Object?>[]),
  );

  Future<void> waitUntil(bool Function() predicate) async {
    while (!predicate()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Starts a 2-player LAN game (host = p0, joiner = p1), attaches both
  /// clients' NetGameControllers to their own ProviderContainer, and plays
  /// p0's opening attack (seed 1: p0 holds 'strife', an attack targeting
  /// shoes; p1 holds 'prayer', a defense card) so a pendingInterrupt with
  /// p1 as defender is live by the time this returns. Short
  /// defenseResponseTimeout so countdown/timeout tests don't need to wait
  /// the real default 20s.
  Future<
      ({
        HostServer host,
        GameClient p0Client,
        GameClient p1Client,
        ProviderContainer p0Container,
        ProviderContainer p1Container,
      })> setUpPendingInterrupt(
    WidgetTester tester, {
    Duration? defenseResponseTimeout = const Duration(seconds: 2),
  }) async {
    final host = HostServer(
      hostDisplayName: 'Mumu',
      defenseResponseTimeout: defenseResponseTimeout,
    );
    final p0Client = GameClient();
    final p1Client = GameClient();

    await tester.runAsync(() async {
      final port = await host.start();
      await p0Client.connectToLobby('127.0.0.1', port, 'Mumu');
      await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');
      await waitUntil(() => host.roster.length == 2);

      final p0Started = p0Client.lobbyStarted.first;
      final p1Started = p1Client.lobbyStarted.first;
      host.startGame(seed: 1);
      await p0Started;
      await p1Started;
    });

    final p0Container = ProviderContainer();
    final p1Container = ProviderContainer();
    p0Container.read(appModeControllerProvider.notifier).enterHostLobby(host, p0Client);
    p0Container.read(appModeControllerProvider.notifier).enterNetPlaying();
    p0Container.read(netGameControllerProvider.notifier).attach(p0Client);
    p1Container.read(appModeControllerProvider.notifier).enterWaitingForHost(p1Client);
    p1Container.read(appModeControllerProvider.notifier).enterNetPlaying();
    p1Container.read(netGameControllerProvider.notifier).attach(p1Client);

    await tester.runAsync(() async {
      p0Client.dispatch(const DrawCard(playerId: 'p0'));
      await waitUntil(() => host.state?.hasDrawnThisTurn == true);
      final strifeId =
          host.state!.playerById('p0').hand.firstWhere((c) => c.defId == 'strife').instanceId;
      p0Client.dispatch(PlayCard(playerId: 'p0', cardInstanceId: strifeId, targetPlayerId: 'p1'));
      await waitUntil(() => host.state?.pendingInterrupt != null);
      // Let the StateMessage carrying the interrupt (and its deadline)
      // actually reach both clients before the test proceeds.
      await waitUntil(() => p0Container.read(gameStateProvider)?.pendingInterrupt != null);
      await waitUntil(() => p1Container.read(gameStateProvider)?.pendingInterrupt != null);
    });

    addTearDown(() async {
      // Real socket teardown needs the real event loop, same as setup
      // above - and closing the clients/host first (before disposing the
      // containers listening to them) ensures no further StateMessage can
      // arrive and schedule a riverpod provider-refresh timer after the
      // containers are gone, which is what trips flutter_test's
      // no-pending-timers-after-dispose invariant.
      await tester.runAsync(() async {
        await p0Client.close();
        await p1Client.close();
        await host.stop();
      });
      p0Container.dispose();
      p1Container.dispose();
    });

    return (
      host: host,
      p0Client: p0Client,
      p1Client: p1Client,
      p0Container: p0Container,
      p1Container: p1Container,
    );
  }

  testWidgets(
    'the actual responder (defender) sees a countdown',
    (tester) async {
      final rig = await setUpPendingInterrupt(tester);

      // p1 is the defender (the actual current responder).
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.p1Container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // _ResponseCountdownBar's Timer.periodic must be cancelled before
      // this test ends (flutter_test's binding asserts no pending timers
      // survive a test) - swap to an empty tree and settle so
      // _DefensePromptView/_ResponseCountdownBar actually dispose.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a non-responder (the attacker) does not see a countdown',
    (tester) async {
      final rig = await setUpPendingInterrupt(tester);

      // p0 is the attacker - not the responder - and must never see a
      // countdown (it would wrongly imply p0 can act).
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.p0Container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'the non-responder sees a calm waiting-for-response view, not the interactive defense prompt',
    (tester) async {
      final rig = await setUpPendingInterrupt(tester);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.p0Container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      // Names the defender being waited on, without any defense-card
      // chooser controls (those belong only to the responder's own
      // screen).
      expect(find.textContaining('Waiting for'), findsOneWidget);
      expect(find.text('TAKE THE HIT'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'no hand data leaks into the waiting view for a non-responder bystander',
    (tester) async {
      final rig = await setUpPendingInterrupt(tester);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.p0Container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      // The attacker's own reconstructed GameState only ever holds
      // placeholder cards for every other player's hand (see
      // reconstructFromFiltered) - assert directly against the data source
      // the waiting view (and everything else on this screen) reads from,
      // not just the absence of specific card names in the rendered text.
      final reconstructed = rig.p0Container.read(gameStateProvider)!;
      final defenderHand = reconstructed.playerById('p1').hand;
      expect(defenderHand, isNotEmpty);
      expect(defenderHand.every((c) => c.defId == '__hidden__'), isTrue);
    },
  );

  testWidgets(
    'a system timeout produces a shared resolution beat naming the timed-out player',
    (tester) async {
      final rig = await setUpPendingInterrupt(
        tester,
        defenseResponseTimeout: const Duration(milliseconds: 300),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.p0Container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();

      // p1 never responds - let the host's short timeout fire and land
      // the attack, then let that resolved state reach p0's client.
      await tester.runAsync(() async {
        await waitUntil(() => rig.host.state?.pendingInterrupt == null);
        await waitUntil(() => rig.p0Container.read(gameStateProvider)?.pendingInterrupt == null);
      });
      await tester.pump();

      expect(find.textContaining('ran out of time'), findsOneWidget);
      expect(find.textContaining('Zoe'), findsWidgets);

      // Auto-dismisses without any tap.
      await tester.pump(const Duration(milliseconds: 2600));
      expect(find.textContaining('ran out of time'), findsNothing);
    },
  );

  testWidgets('a block produces a shared resolution beat naming the defense card', (tester) async {
    final rig = await setUpPendingInterrupt(tester);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: rig.p0Container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final prayerId =
          rig.host.state!.playerById('p1').hand.firstWhere((c) => c.defId == 'prayer').instanceId;
      rig.p1Client.dispatch(DeclareDefense(playerId: 'p1', cardInstanceId: prayerId));
      await waitUntil(() => rig.host.state?.pendingInterrupt == null);
      await waitUntil(() => rig.p0Container.read(gameStateProvider)?.pendingInterrupt == null);
    });
    await tester.pump();

    expect(find.textContaining('blocked the attack'), findsOneWidget);

    // Drain the beat's own auto-dismiss Timer before the test ends -
    // otherwise it's still pending when the widget tree is torn down,
    // which flutter_test's binding treats as a leaked timer.
    await tester.pump(const Duration(milliseconds: 2600));
  });

  testWidgets(
    'hotseat never shows a countdown, even with a pending interrupt (no deadline is ever set)',
    (tester) async {
      // No real HostServer/GameClient involved at all - hotseat's
      // GameController never has a responseDeadlineEpochMs concept, so
      // responseDeadlineEpochMsProvider is gated off purely by AppMode
      // (see game_providers.dart), never even reaching a null-vs-set
      // question the way LAN does.
      final base = newGame(playerNames: ['Alice', 'Bob'], seed: 1);
      final defenderId = base.players[1].id;
      final crafted = base.copyWith(
        pendingInterrupt: PendingAttack(
          attackCardDefId: 'strife',
          attackCardInstanceId: 'test-strife',
          attackerId: base.players[0].id,
          defenderId: defenderId,
          targetArmor: ArmorType.shoes,
        ),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(gameControllerProvider.notifier).state = GameUiState(state: crafted);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text("I'm ready"));
      await tester.pump();

      expect(currentActorId(crafted), defenderId);
      expect(find.text('DEFENSE'), findsOneWidget);
      expect(find.text('BOB'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
}
