import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('restore cards', () {
    test('Renewal: Weakened -> Strong', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['renewal'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.belt: ArmorCondition.weakened},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.belt),
        ),
      );
      expect(result.players[0].armorOf(ArmorType.belt).condition, ArmorCondition.strong);
    });

    test('Renewal cannot target a Strong or Lost piece', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['renewal'],
          1: [],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final reason = expectFailure(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.belt),
        ),
      );
      expect(reason, contains('right condition'));
    });

    test('Armor Bearer: Lost -> Strong', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.sword: ArmorCondition.lost},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.sword),
        ),
      );
      expect(result.players[0].armorOf(ArmorType.sword).condition, ArmorCondition.strong);
    });

    test('Fasting: fully restores a Lost piece and schedules a skipped next turn', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fasting'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final afterPlay = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      expect(afterPlay.players[0].armorOf(ArmorType.helmet).condition, ArmorCondition.strong);
      expect(afterPlay.players[0].fastingScheduled, isTrue);
      expect(afterPlay.players[0].isFasting, isFalse);
    });

    test('Fasting can target a Strong piece (any condition is valid)', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fasting'],
          1: [],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      expect(result.players[0].armorOf(ArmorType.helmet).condition, ArmorCondition.strong);
      expect(result.players[0].fastingScheduled, isTrue);
    });

    test('Fasting can target a Weakened piece', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fasting'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.shield: ArmorCondition.weakened},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.shield),
        ),
      );

      expect(result.players[0].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
      expect(result.players[0].fastingScheduled, isTrue);
    });

    test('fasting player still draws but cannot play on their skipped turn', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fasting'],
          1: ['renewal'],
        },
        armorOverrides: {
          0: {
            ArmorType.helmet: ArmorCondition.lost,
            // Kept weakened (not restored by Fasting) so Alice isn't
            // fully restored when her turn comes back around - this test
            // is about the skip-play-step mechanic, not the win condition.
            ArmorType.sword: ArmorCondition.weakened,
          },
        },
        drawPileDefIds: ['prayer', 'prayer'],
      );
      final fastingCardId = state.players[0].hand.first.instanceId;
      state = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: fastingCardId, targetArmor: ArmorType.helmet),
        ),
      );
      state = expectSuccess(applyAction(state, const EndTurn(playerId: 'p0')));

      // Bob's turn.
      state = expectSuccess(applyAction(state, const DrawCard(playerId: 'p1')));
      final renewalId = state.players[1].hand.firstWhere((c) => c.defId == 'renewal').instanceId;
      // Bob has no weakened armor to renew onto, so just end turn.
      state = expectSuccess(
        applyAction(state, DiscardCard(playerId: 'p1', cardInstanceId: renewalId)),
      );
      state = expectSuccess(applyAction(state, const EndTurn(playerId: 'p1')));

      // Alice's skipped turn: she is now active and fasting.
      expect(state.activePlayer.id, 'p0');
      expect(state.activePlayer.isFasting, isTrue);

      final beforeDraw = state.activePlayer.hand.length;
      state = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));
      expect(state.activePlayer.hand.length, beforeDraw + 1);
      expect(state.eventLog.whereType<TurnSkipped>(), hasLength(1));

      final anyCardId = state.activePlayer.hand.first.instanceId;
      final reason = expectFailure(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: anyCardId)),
      );
      expect(reason, contains('fasting'));

      // She can still end her turn without playing.
      final afterEnd = expectSuccess(applyAction(state, const EndTurn(playerId: 'p0')));
      expect(afterEnd.activePlayer.id, 'p1');
    });
  });

  group('event cards', () {
    test('Jericho March: all Weakened pieces across all players become Lost', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['jericho_march'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.shield: ArmorCondition.weakened},
          1: {ArmorType.helmet: ArmorCondition.weakened, ArmorType.sword: ArmorCondition.strong},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      expect(result.players[0].armorOf(ArmorType.shield).condition, ArmorCondition.lost);
      expect(result.players[1].armorOf(ArmorType.helmet).condition, ArmorCondition.lost);
      expect(result.players[1].armorOf(ArmorType.sword).condition, ArmorCondition.strong);
    });

    test('Road to Damascus steals a random card from the target player deterministically', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['road_to_damascus'],
          1: ['prayer', 'renewal', 'fasting'],
        },
        seed: 99,
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );

      expect(result.players[1].hand, hasLength(2));
      expect(result.players[0].hand, hasLength(1));
      final stolenEvent = result.eventLog.whereType<CardStolen>().single;
      expect(result.players[0].hand.first.defId, stolenEvent.cardDefId);
    });

    test('Road to Damascus cannot target a player with an empty hand', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['road_to_damascus'],
          1: [],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final reason = expectFailure(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );
      expect(reason, contains('no cards to steal'));
    });

    test('Wilderness Season opens a tracked group-discard obligation for every player with cards', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['wilderness_season', 'prayer'],
          1: ['renewal'],
        },
      );
      final cardId = state.players[0].hand.firstWhere((c) => c.defId == 'wilderness_season').instanceId;
      final afterPlay = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      expect(afterPlay.eventLog.whereType<CardPlayed>().last.cardDefId, 'wilderness_season');
      expect(afterPlay.pendingGroupDiscard, isNotNull);
      expect(afterPlay.pendingGroupDiscard!.owedPlayerIds, {'p0', 'p1'});

      // Alice (the active player, already used her turn action playing
      // Wilderness Season) discards explicitly.
      final aliceCardId = afterPlay.players[0].hand.first.instanceId;
      final afterAlice = expectSuccess(
        applyAction(afterPlay, DiscardCard(playerId: 'p0', cardInstanceId: aliceCardId)),
      );
      expect(afterAlice.pendingGroupDiscard!.owedPlayerIds, {'p1'});

      // Bob, who is NOT the active player, can still discard because he's
      // owed by the group-discard obligation.
      final bobCardId = afterAlice.players[1].hand.first.instanceId;
      final afterBob = expectSuccess(
        applyAction(afterAlice, DiscardCard(playerId: 'p1', cardInstanceId: bobCardId)),
      );

      expect(afterBob.pendingGroupDiscard, isNull);
      expect(afterBob.players[0].hand, isEmpty);
      expect(afterBob.players[1].hand, isEmpty);
      expect(afterBob.discardPile, hasLength(3)); // wilderness_season + 2 discards
    });

    test('Wilderness Season auto-excludes a player with an empty hand', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['wilderness_season', 'prayer'],
          1: [],
        },
      );
      final cardId = state.players[0].hand.firstWhere((c) => c.defId == 'wilderness_season').instanceId;
      final afterPlay = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      // Bob has nothing to discard, so only Alice owes.
      expect(afterPlay.pendingGroupDiscard!.owedPlayerIds, {'p0'});

      final aliceCardId = afterPlay.players[0].hand.first.instanceId;
      final afterAlice = expectSuccess(
        applyAction(afterPlay, DiscardCard(playerId: 'p0', cardInstanceId: aliceCardId)),
      );
      expect(afterAlice.pendingGroupDiscard, isNull);
    });

    test('a player not owed a group discard cannot discard while one is pending', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['wilderness_season', 'prayer'],
          1: ['renewal'],
          2: [],
        },
      );
      final cardId = state.players[0].hand.firstWhere((c) => c.defId == 'wilderness_season').instanceId;
      final afterPlay = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      // Carl has no cards, so he's not in the owed set and shouldn't be
      // able to "discard" (nothing to discard, and not owed anyway).
      expect(afterPlay.pendingGroupDiscard!.owedPlayerIds, {'p0', 'p1'});
      final reason = expectFailure(
        applyAction(afterPlay, const DiscardCard(playerId: 'p2', cardInstanceId: 'nonexistent')),
      );
      expect(reason, contains('not in that player'));
    });

    test('other action types are rejected while a group discard is pending', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['wilderness_season', 'prayer'],
          1: ['renewal'],
        },
      );
      final cardId = state.players[0].hand.firstWhere((c) => c.defId == 'wilderness_season').instanceId;
      final afterPlay = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      final reason = expectFailure(applyAction(afterPlay, const EndTurn(playerId: 'p0')));
      expect(reason, contains('group discard'));
    });
  });

  group('deck exhaustion / reshuffle', () {
    test('drawing with an empty draw pile reshuffles the discard pile', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        drawPileDefIds: [],
      );
      state = state.copyWith(
        discardPile: [
          const CardInstance(instanceId: 'd0', defId: 'prayer'),
          const CardInstance(instanceId: 'd1', defId: 'renewal'),
        ],
        hasDrawnThisTurn: false,
      );

      final result = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));

      expect(result.discardPile, isEmpty);
      expect(result.players[0].hand, hasLength(1));
      expect(result.drawPile, hasLength(1));
      expect(result.eventLog.whereType<DeckReshuffled>(), hasLength(1));
    });

    test('drawing with both piles empty ends the game (deck exhausted) instead of erroring', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        drawPileDefIds: [],
      );
      state = state.copyWith(hasDrawnThisTurn: false);

      final result = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));
      expect(result.players[0].hand, isEmpty);
      expect(result.isGameOver, isTrue);
      expect(result.winner!.type, WinType.deckExhausted);
    });
  });
}
