import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('undefended attacks', () {
    test('specificArmorOnPlayer attack weakens a Strong piece', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: [], // no defense cards -> lands immediately
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );

      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.weakened);
      expect(result.pendingInterrupt, isNull);
      expect(result.eventLog.whereType<ArmorWeakened>(), hasLength(1));
      expect(result.discardPile.map((c) => c.defId), contains('doubt'));
    });

    test('second hit on a Weakened piece loses it', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: [],
        },
        armorOverrides: {
          1: {ArmorType.shield: ArmorCondition.weakened},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );

      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.lost);
      expect(result.eventLog.whereType<ArmorLost>(), hasLength(1));
    });

    test('anyPieceOnPlayer attack (Fiery Dart) targets chosen armor', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fiery_dart'],
          1: [],
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
            targetArmor: ArmorType.sword,
          ),
        ),
      );

      expect(result.players[1].armorOf(ArmorType.sword).condition, ArmorCondition.weakened);
    });

    test("Goliath's Taunt double-hits Strong straight to Lost", () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['goliaths_taunt'],
          1: [],
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

      expect(result.players[1].armorOf(ArmorType.helmet).condition, ArmorCondition.lost);
      expect(result.eventLog.whereType<ArmorLost>(), hasLength(1));
      expect(result.eventLog.whereType<ArmorWeakened>(), isEmpty);
    });

    test('cannot attack an already-lost piece', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: [],
        },
        armorOverrides: {
          1: {ArmorType.shield: ArmorCondition.lost},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final reason = expectFailure(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );
      expect(reason, contains('already lost'));
    });

    test('cannot target yourself with an attack', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: [],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final reason = expectFailure(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p0'),
        ),
      );
      expect(reason, contains('Cannot target yourself'));
    });

    test('cannot attack an eliminated player', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: [],
        },
        armorOverrides: {
          1: {
            for (final t in ArmorType.values) t: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final reason = expectFailure(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );
      expect(reason, contains('already eliminated'));
    });
  });

  group('attack opens a defense window when defender holds a defense card', () {
    test('pendingInterrupt is set instead of landing immediately', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );

      expect(result.pendingInterrupt, isNotNull);
      expect(result.pendingInterrupt!.defenderId, 'p1');
      expect(result.pendingInterrupt!.attackerId, 'p0');
      // Armor untouched until the interrupt resolves.
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
    });

    test('only DeclareDefense/DeclineDefense are valid while pending', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final withPending = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetPlayerId: 'p1'),
        ),
      );

      final reason = expectFailure(applyAction(withPending, const DrawCard(playerId: 'p0')));
      expect(reason, contains('awaiting a defense response'));
    });
  });
}
