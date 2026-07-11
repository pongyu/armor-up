import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('eliminated player hand cleanup', () {
    test('elimination via a normal landed attack discards the hand', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['fiery_dart'],
          1: ['renewal', 'fasting'],
          2: [],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final beforeDiscardCount = state.discardPile.length;

      // Bob holds no defense card (renewal/fasting are restore cards), so
      // this attack lands immediately - no DeclareDefense/DeclineDefense
      // step is needed.
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(
            playerId: 'p0',
            cardInstanceId: cardId,
            targetPlayerId: 'p1',
            targetArmor: ArmorType.helmet,
          ),
        ),
      );

      // 3-player game, so eliminating p1 doesn't end the game - the hand
      // cleanup must happen independent of the elimination-win check.
      expect(result.isGameOver, isFalse);
      expect(result.players[1].isEliminated, isTrue);
      expect(result.players[1].hand, isEmpty);
      // fiery_dart (the attack card played) + renewal/fasting (Bob's
      // discarded hand).
      expect(result.discardPile.length, beforeDiscardCount + 3);
      expect(
        result.discardPile.map((c) => c.defId),
        containsAll(['renewal', 'fasting']),
      );

      final eliminatedEvent = result.eventLog.whereType<PlayerEliminated>().single;
      expect(eliminatedEvent.playerId, 'p1');
      expect(eliminatedEvent.cardsDiscarded, 2);
    });

    test('elimination via a reflected attack (It Is Written) discards the original attacker\'s hand', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['goliaths_taunt', 'renewal', 'fasting'],
          1: ['it_is_written'],
          2: [],
        },
        armorOverrides: {
          0: {
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
            // helmet stays Strong; Goliath's Taunt (double hit) on it will
            // send it straight to Lost when reflected back, eliminating p0.
          },
        },
      );
      final attackCardId = state.players[0].hand.firstWhere((c) => c.defId == 'goliaths_taunt').instanceId;
      final pending = expectSuccess(
        applyAction(
          state,
          PlayCard(
            playerId: 'p0',
            cardInstanceId: attackCardId,
            targetPlayerId: 'p1',
            targetArmor: ArmorType.helmet,
          ),
        ),
      );
      final iiwId = pending.players[1].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: iiwId)),
      );

      // p0 (original attacker, now reflected defender) holds no defense
      // card (renewal/fasting are restore cards), so the reflected double
      // hit lands immediately and eliminates them.
      expect(result.players[0].isEliminated, isTrue);
      expect(result.players[0].hand, isEmpty);
      expect(
        result.discardPile.map((c) => c.defId),
        containsAll(['renewal', 'fasting']),
      );
      final eliminatedEvent = result.eventLog.whereType<PlayerEliminated>().single;
      expect(eliminatedEvent.playerId, 'p0');
      expect(eliminatedEvent.cardsDiscarded, 2);
    });

    test('Jericho March eliminating two players at once discards both hands', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['jericho_march'],
          1: ['prayer', 'renewal'],
          2: ['fasting'],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
          2: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      expect(result.players[1].isEliminated, isTrue);
      expect(result.players[2].isEliminated, isTrue);
      expect(result.players[1].hand, isEmpty);
      expect(result.players[2].hand, isEmpty);
      expect(
        result.discardPile.map((c) => c.defId),
        containsAll(['jericho_march', 'prayer', 'renewal', 'fasting']),
      );
      expect(result.eventLog.whereType<PlayerEliminated>(), hasLength(2));
      expect(
        result.eventLog.whereType<PlayerEliminated>().map((e) => e.playerId),
        containsAll(['p1', 'p2']),
      );
    });

    test('an already-eliminated player is never re-processed', () {
      // p1 starts already eliminated (all Lost) with an empty hand, as if
      // a prior hit had already triggered cleanup. A second attack that
      // targets an already-Lost piece must not log another
      // PlayerEliminated or touch an already-empty hand/discard pile.
      // p1 starts already eliminated (all Lost) with an empty hand, as if
      // a prior hit had already triggered cleanup. Jericho March (which
      // sweeps every player's Weakened pieces) resolves again here,
      // targeting p2's own Weakened piece - p1 has nothing left that
      // Jericho March could touch (all pieces already Lost, not
      // Weakened), so it must not be re-flagged as newly eliminated or
      // have its already-empty hand/discard state touched again.
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['jericho_march'],
          1: [],
          2: ['prayer'],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.lost,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
          2: {ArmorType.shield: ArmorCondition.weakened},
        },
      );
      expect(state.players[1].isEliminated, isTrue);
      final beforeDiscardCount = state.discardPile.length;

      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      // p2's weakened shield goes to Lost but p2 still has other Strong
      // pieces, so p2 is not eliminated; p1 was already eliminated before
      // this resolution and must not be re-processed.
      expect(result.players[2].isEliminated, isFalse);
      expect(result.eventLog.whereType<PlayerEliminated>(), isEmpty);
      expect(result.players[1].hand, isEmpty);
      // Only jericho_march itself was discarded; p1's already-empty hand
      // contributed nothing.
      expect(result.discardPile.length, beforeDiscardCount + 1);
    });

    test('eliminated player is skipped in turn order with an empty hand', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['fiery_dart'],
          1: ['renewal'],
          2: [],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      // Bob holds no defense card (renewal is a restore card), so this
      // attack lands immediately.
      var result = expectSuccess(
        applyAction(
          state,
          PlayCard(
            playerId: 'p0',
            cardInstanceId: cardId,
            targetPlayerId: 'p1',
            targetArmor: ArmorType.helmet,
          ),
        ),
      );
      expect(result.players[1].isEliminated, isTrue);
      expect(result.players[1].hand, isEmpty);

      result = expectSuccess(applyAction(result, const EndTurn(playerId: 'p0')));
      // Turn order skips eliminated p1 straight to p2.
      expect(result.activePlayer.id, 'p2');
    });
  });
}
