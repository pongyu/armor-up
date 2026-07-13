import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';

import 'package:armor_up/screens/game_screen.dart';
import 'package:armor_up/state/game_controller.dart';
import 'package:armor_up/state/turn_actor.dart';

/// Covers Phase 3 Part 2.5: the RestorationImminent banner (shown once on
/// the triggering event, auto-dismissing, non-blocking) and the persistent
/// "fully armored" marker (derived from PlayerState.isFullyRestored, not
/// from the event, so it self-corrects as the board changes).
void main() {
  Future<ProviderContainer> pumpGame(
    WidgetTester tester,
    GameState state,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(gameControllerProvider.notifier).state =
        GameUiState(state: state);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text("I'm ready"));
    await tester.pump();

    return container;
  }

  /// A player with all-Strong armor and `wasEverBroken: true` - satisfies
  /// `isFullyRestored` (which requires having been broken at some point,
  /// not just an untouched starting state).
  PlayerState fullyRestoredPlayer(PlayerState p) => p.copyWith(
        armor: startingArmorSet(),
        wasEverBroken: true,
      );

  GameState baseState({bool restorationWinEnabled = true}) => newGame(
        playerNames: ['Alice', 'Bob'],
        seed: 1,
        restorationWinEnabled: restorationWinEnabled,
      );

  String bannerText(String playerName) =>
      '${playerName.toUpperCase()} STANDS FULLY ARMORED - '
      'STOP THEM BEFORE THEIR NEXT TURN!';

  testWidgets('banner shows on a RestorationImminent event and auto-dismisses', (tester) async {
    final base = baseState();
    final container = await pumpGame(tester, base);

    final withEvent = base.appendEvent(
      const RestorationImminent(turnNumber: 1, playerId: 'p0'),
    );
    container.read(gameControllerProvider.notifier).state =
        GameUiState(state: withEvent);
    await tester.pump();

    expect(find.text(bannerText('Alice')), findsOneWidget);

    // Auto-dismiss fires via a delayed Future scheduled in build - pump
    // past the 4s window.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text(bannerText('Alice')), findsNothing);
  });

  testWidgets('tapping the banner dismisses it immediately', (tester) async {
    final base = baseState();
    final container = await pumpGame(tester, base);

    final withEvent = base.appendEvent(
      const RestorationImminent(turnNumber: 1, playerId: 'p0'),
    );
    container.read(gameControllerProvider.notifier).state =
        GameUiState(state: withEvent);
    await tester.pump();
    expect(find.text(bannerText('Alice')), findsOneWidget);

    await tester.tap(find.text(bannerText('Alice')));
    await tester.pump();

    expect(find.text(bannerText('Alice')), findsNothing);
  });

  testWidgets('board beneath the banner stays interactive (Draw button still tappable)',
      (tester) async {
    final base = baseState();
    final container = await pumpGame(tester, base);

    final withEvent = base.appendEvent(
      const RestorationImminent(turnNumber: 1, playerId: 'p0'),
    );
    container.read(gameControllerProvider.notifier).state =
        GameUiState(state: withEvent);
    await tester.pump();
    expect(find.text(bannerText('Alice')), findsOneWidget);

    await tester.tap(find.text('Draw'));
    await tester.pump();

    expect(container.read(gameControllerProvider)!.state.hasDrawnThisTurn, isTrue);
  });

  testWidgets('no banner when the event was already in the log before this host mounted',
      (tester) async {
    // Simulates resuming an existing game (or a rebuild) - only events
    // appended AFTER the host mounts should announce.
    final base = baseState();
    final withOldEvent = base.appendEvent(
      const RestorationImminent(turnNumber: 1, playerId: 'p0'),
    );

    await pumpGame(tester, withOldEvent);
    // The event was already present at mount time - no banner replay.
    expect(find.text(bannerText('Alice')), findsNothing);
  });

  group('fully-armored marker', () {
    testWidgets('shown on the fully-restored player\'s compact row (opponent view)',
        (tester) async {
      final base = baseState();
      final crafted = base.copyWith(
        players: [
          for (final p in base.players)
            if (p.id != currentActorId(base)) fullyRestoredPlayer(p) else p,
        ],
      );

      await pumpGame(tester, crafted);

      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('shown on the active player\'s own "Your Armor" panel', (tester) async {
      final base = baseState();
      final actorId = currentActorId(base);
      final crafted = base.copyWith(
        players: [
          for (final p in base.players)
            if (p.id == actorId) fullyRestoredPlayer(p) else p,
        ],
      );

      await pumpGame(tester, crafted);

      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('absent when no player is fully restored', (tester) async {
      final base = baseState();
      await pumpGame(tester, base);

      expect(find.byIcon(Icons.emoji_events), findsNothing);
    });

    testWidgets('disappears immediately once the player drops below Strong', (tester) async {
      final base = baseState();
      final actorId = currentActorId(base);
      final restored = base.copyWith(
        players: [
          for (final p in base.players)
            if (p.id == actorId) fullyRestoredPlayer(p) else p,
        ],
      );

      final container = await pumpGame(tester, restored);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);

      final damaged = restored.copyWith(
        players: [
          for (final p in restored.players)
            if (p.id == actorId)
              p.withArmorCondition(ArmorType.helmet, ArmorCondition.weakened)
            else
              p,
        ],
      );
      container.read(gameControllerProvider.notifier).state =
          GameUiState(state: damaged);
      await tester.pump();

      expect(find.byIcon(Icons.emoji_events), findsNothing);
    });

    testWidgets('never rendered in basic mode (restorationWinEnabled: false)', (tester) async {
      final base = baseState(restorationWinEnabled: false);
      final actorId = currentActorId(base);
      final crafted = base.copyWith(
        players: [
          for (final p in base.players)
            if (p.id == actorId) fullyRestoredPlayer(p) else p,
        ],
      );

      await pumpGame(tester, crafted);

      expect(find.byIcon(Icons.emoji_events), findsNothing);
    });
  });
}
