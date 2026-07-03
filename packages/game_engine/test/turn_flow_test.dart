import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('setup', () {
    test('newGame deals 6 strong armor and 5 cards to each player', () {
      final state = newGame(playerNames: ['Alice', 'Bob'], seed: 42);

      expect(state.players, hasLength(2));
      for (final player in state.players) {
        expect(player.armor, hasLength(6));
        expect(
          player.armor.every((a) => a.condition == ArmorCondition.strong),
          isTrue,
        );
        expect(player.hand, hasLength(5));
      }
      expect(state.drawPile.length, standardDeckSize - 2 * 5);
    });

    test('rejects fewer than 2 or more than 6 players', () {
      expect(() => newGame(playerNames: ['Solo'], seed: 1), throwsArgumentError);
      expect(
        () => newGame(
          playerNames: List.generate(7, (i) => 'P$i'),
          seed: 1,
        ),
        throwsArgumentError,
      );
    });

    test('same seed produces identical games', () {
      final a = newGame(playerNames: ['Alice', 'Bob', 'Carl'], seed: 7);
      final b = newGame(playerNames: ['Alice', 'Bob', 'Carl'], seed: 7);

      for (var i = 0; i < a.players.length; i++) {
        expect(
          a.players[i].hand.map((c) => c.defId).toList(),
          b.players[i].hand.map((c) => c.defId).toList(),
        );
      }
      expect(
        a.drawPile.map((c) => c.defId).toList(),
        b.drawPile.map((c) => c.defId).toList(),
      );
    });
  });

  group('draw', () {
    test('drawing adds a card to hand and marks hasDrawnThisTurn', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        drawPileDefIds: ['prayer', 'renewal'],
      );
      state = state.copyWith(hasDrawnThisTurn: false);

      final result = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));

      expect(result.players[0].hand, hasLength(1));
      expect(result.players[0].hand.single.defId, 'prayer');
      expect(result.hasDrawnThisTurn, isTrue);
      expect(result.eventLog.whereType<CardDrawn>(), hasLength(1));
    });

    test('cannot draw twice in one turn', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        drawPileDefIds: ['prayer'],
      );
      final reason = expectFailure(applyAction(state, const DrawCard(playerId: 'p0')));
      expect(reason, contains('Already drew'));
    });

    test('non-active player cannot draw', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        drawPileDefIds: ['prayer'],
      );
      state = state.copyWith(hasDrawnThisTurn: false);
      final reason = expectFailure(applyAction(state, const DrawCard(playerId: 'p1')));
      expect(reason, contains('active player'));
    });
  });

  group('discard', () {
    test('discard removes card from hand into discard pile', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['prayer', 'renewal'],
          1: [],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(state, DiscardCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      expect(result.players[0].hand, hasLength(1));
      expect(result.discardPile, hasLength(1));
      expect(result.eventLog.whereType<CardDiscarded>(), hasLength(1));
    });

    test('cannot end turn over hand limit without discarding first', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['prayer', 'renewal', 'fasting', 'armor_bearer', 'doubt', 'fiery_dart'],
          1: [],
        },
      );
      final reason = expectFailure(applyAction(state, const EndTurn(playerId: 'p0')));
      expect(reason, contains('discard down to the hand limit'));
    });
  });

  group('end turn / turn rotation', () {
    test('end turn advances active player and resets hasDrawnThisTurn', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      final result = expectSuccess(applyAction(state, const EndTurn(playerId: 'p0')));

      expect(result.activePlayerIndex, 1);
      expect(result.hasDrawnThisTurn, isFalse);
      expect(result.turnNumber, state.turnNumber + 1);
    });

    test('wraps around from last player to first', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      state = state.copyWith(activePlayerIndex: 1);
      final result = expectSuccess(applyAction(state, const EndTurn(playerId: 'p1')));
      expect(result.activePlayerIndex, 0);
    });

    test('must draw before ending turn', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      state = state.copyWith(hasDrawnThisTurn: false);
      final reason = expectFailure(applyAction(state, const EndTurn(playerId: 'p0')));
      expect(reason, contains('Must draw'));
    });

    test('only active player may end their turn', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      final reason = expectFailure(applyAction(state, const EndTurn(playerId: 'p1')));
      expect(reason, contains('active player'));
    });
  });

  group('invalid actions', () {
    test('playing a card not in hand fails', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      final reason = expectFailure(
        applyAction(
          state,
          const PlayCard(playerId: 'p0', cardInstanceId: 'nonexistent'),
        ),
      );
      expect(reason, contains('not in the active player'));
    });

    test('playing a defense card outside an interrupt fails', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['prayer'],
          1: [],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final reason = expectFailure(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId),
        ),
      );
      expect(reason, contains('Defense cards can only be played'));
    });

    test('actions after game over are rejected', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      state = state.copyWith(
        winner: const WinResult(winnerId: 'p0', type: WinType.elimination),
      );
      final reason = expectFailure(applyAction(state, const EndTurn(playerId: 'p1')));
      expect(reason, contains('already ended'));
    });
  });
}
