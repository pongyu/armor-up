import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';

import 'package:armor_up/screens/game_screen.dart';
import 'package:armor_up/state/game_controller.dart';
import 'package:armor_up/state/turn_actor.dart';

/// Covers the Phase 3 fix: a restore card with zero eligible targets on the
/// player's own armor (e.g. Renewal when nothing is Weakened) must show up
/// disabled/grayed in hand, the same way defense cards always are - rather
/// than letting the player select it and discover only via a dead-end
/// target-selection screen that it has nowhere to go.
void main() {
  Future<ProviderContainer> pumpWithHand(
    WidgetTester tester, {
    required List<CardInstance> hand,
    required List<ArmorPiece> armor,
  }) async {
    // Tall aspect ratio so the LayoutBuilder in _MainBoardView picks the
    // portrait board branch (maxHeight > maxWidth), which is where
    // _FannedHand (and its isCardDisabled) renders.
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final base = newGame(playerNames: ['Alice', 'Bob'], seed: 1);
    final actorId = currentActorId(base);
    final crafted = base.copyWith(
      players: [
        for (final p in base.players)
          if (p.id == actorId) p.copyWith(hand: hand, armor: armor) else p,
      ],
      hasDrawnThisTurn: true,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(gameControllerProvider.notifier).state =
        GameUiState(state: crafted);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();

    // GameScreen gates the board behind a pass-the-device screen until the
    // acting player taps through it.
    await tester.tap(find.text("I'm ready"));
    await tester.pump();

    return container;
  }

  /// True if the CardWidget rendering [cardId] sits under a ColorFiltered
  /// ancestor - _HandCard's only mechanism for showing "disabled".
  bool isRenderedDisabled(WidgetTester tester, String cardId) {
    final cardWidgetFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == 'CardWidget' &&
          (widget as dynamic).def.id == cardId,
    );
    expect(cardWidgetFinder, findsWidgets);
    final ancestorFilters = find.ancestor(
      of: cardWidgetFinder.first,
      matching: find.byType(ColorFiltered),
    );
    return ancestorFilters.evaluate().isNotEmpty;
  }

  testWidgets('Renewal is disabled in hand when no armor is Weakened', (tester) async {
    await pumpWithHand(
      tester,
      hand: const [CardInstance(instanceId: 'hand-renewal', defId: 'renewal')],
      armor: startingArmorSet(), // all Strong - Renewal has nowhere to go
    );

    expect(isRenderedDisabled(tester, 'renewal'), isTrue);
  });

  testWidgets('Renewal is enabled in hand when a piece is Weakened', (tester) async {
    final armor = [
      for (final piece in startingArmorSet())
        if (piece.type == ArmorType.helmet)
          piece.copyWith(condition: ArmorCondition.weakened)
        else
          piece,
    ];
    await pumpWithHand(
      tester,
      hand: const [CardInstance(instanceId: 'hand-renewal', defId: 'renewal')],
      armor: armor,
    );

    expect(isRenderedDisabled(tester, 'renewal'), isFalse);
  });

  testWidgets('Armor Bearer is disabled in hand when no armor is Lost', (tester) async {
    await pumpWithHand(
      tester,
      hand: const [CardInstance(instanceId: 'hand-ab', defId: 'armor_bearer')],
      armor: startingArmorSet(), // all Strong - Armor Bearer has nowhere to go
    );

    expect(isRenderedDisabled(tester, 'armor_bearer'), isTrue);
  });

  testWidgets('Fasting is never disabled by target eligibility (accepts any condition)',
      (tester) async {
    await pumpWithHand(
      tester,
      hand: const [CardInstance(instanceId: 'hand-fast', defId: 'fasting')],
      armor: startingArmorSet(),
    );

    expect(isRenderedDisabled(tester, 'fasting'), isFalse);
  });
}
