import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('elimination win', () {
    test('last hit that eliminates the only remaining opponent ends the game', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fiery_dart'],
          1: [],
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

      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.elimination));
      expect(result.eventLog.whereType<GameEnded>().single.winType, WinType.elimination);
    });

    test('with 3 players, eliminating one does not end the game', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['fiery_dart'],
          1: [],
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

      expect(result.isGameOver, isFalse);
      expect(result.players[1].isEliminated, isTrue);
    });

    test('no actions are accepted after the game ends', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      state = state.copyWith(
        winner: const WinResult(winnerId: 'p0', type: WinType.elimination),
      );
      final reason = expectFailure(applyAction(state, const DrawCard(playerId: 'p1')));
      expect(reason, contains('already ended'));
    });
  });

  group('restoration win', () {
    test('all six pieces Strong at the start of your turn wins by restoration', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.weakened},
        },
      );
      // Restore Alice's last weakened piece mid-turn via a direct state
      // edit (simulating a restore card already resolved), then end Bob's
      // turn so play rotates back to Alice and the start-of-turn check runs.
      final aliceFullyRestored = state.updatePlayer(
        'p0',
        (p) => p.withArmorCondition(ArmorType.helmet, ArmorCondition.strong),
      );
      final atBobsTurn = aliceFullyRestored.copyWith(activePlayerIndex: 1);

      final result = expectSuccess(applyAction(atBobsTurn, const EndTurn(playerId: 'p1')));

      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.restoration));
      expect(result.eventLog.whereType<GameEnded>().single.winType, WinType.restoration);
    });

    test('being fully restored mid-turn (not at turn start) does not win immediately', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['renewal'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.weakened},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      // Alice is now fully restored, but it's still her turn (not the
      // start of it) so the game should not have ended yet.
      expect(result.players[0].isFullyRestored, isTrue);
      expect(result.isGameOver, isFalse);
    });
  });
}
