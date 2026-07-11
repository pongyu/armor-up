import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

GameState _openAttack(
  GameState state, {
  required String attackDefId,
  required String attackerId,
  required String defenderId,
  ArmorType? targetArmor,
}) {
  final attacker = state.playerById(attackerId);
  final cardId = attacker.hand.firstWhere((c) => c.defId == attackDefId).instanceId;
  return expectSuccess(
    applyAction(
      state,
      PlayCard(
        playerId: attackerId,
        cardInstanceId: cardId,
        targetPlayerId: defenderId,
        targetArmor: targetArmor,
      ),
    ),
  );
}

void main() {
  group('system decline (defense-response timeout)', () {
    test('a system decline from the defender resolves the pending attack exactly like a normal decline', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');

      final result = expectSuccess(
        applyAction(pending, const DeclineDefense(playerId: 'p1', isSystemDecline: true)),
      );

      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.weakened);
      // Bob's Prayer is untouched - a system decline does not spend or
      // discard any card, exactly like a normal decline.
      expect(result.players[1].hand, hasLength(1));
    });

    test('a system decline logs DefenseTimedOut with wasHelper false for the defender', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');

      final result = expectSuccess(
        applyAction(pending, const DeclineDefense(playerId: 'p1', isSystemDecline: true)),
      );

      final event = result.eventLog.whereType<DefenseTimedOut>().single;
      expect(event.playerId, 'p1');
      expect(event.wasHelper, isFalse);
    });

    test('a normal (non-system) decline does not log DefenseTimedOut', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');

      final result = expectSuccess(
        applyAction(pending, const DeclineDefense(playerId: 'p1')),
      );

      expect(result.eventLog.whereType<DefenseTimedOut>(), isEmpty);
    });

    test('a system decline on a Fellowship helper advances to the next helper, exactly like a normal decline', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl', 'Dana'],
        hands: {
          0: ['doubt'],
          1: ['fellowship'],
          2: ['prayer'],
          3: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final fellowshipId = pending.players[1].hand.first.instanceId;

      final requested = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: fellowshipId)),
      );
      expect(requested.pendingInterrupt!.fellowshipRequested, isTrue);

      // p2's response window times out.
      final afterTimeout = expectSuccess(
        applyAction(requested, const DeclineDefense(playerId: 'p2', isSystemDecline: true)),
      );
      expect(afterTimeout.pendingInterrupt!.fellowshipRequested, isTrue);
      expect(afterTimeout.pendingInterrupt!.helpersDeclined, contains('p2'));
      final timeoutEvent = afterTimeout.eventLog.whereType<DefenseTimedOut>().single;
      expect(timeoutEvent.playerId, 'p2');
      expect(timeoutEvent.wasHelper, isTrue);

      // p3 (the next/last helper) can still respond normally.
      final p3CardId = afterTimeout.players[3].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(afterTimeout, DeclareDefense(playerId: 'p3', cardInstanceId: p3CardId)),
      );
      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
    });

    test('system decline on the last Fellowship helper falls through to the defender\'s own window', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['doubt'],
          1: ['fellowship', 'prayer'],
          2: [],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final fellowshipId = pending.players[1].hand.firstWhere((c) => c.defId == 'fellowship').instanceId;

      final requested = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: fellowshipId)),
      );

      // The only other player's window times out.
      final afterTimeout = expectSuccess(
        applyAction(requested, const DeclineDefense(playerId: 'p2', isSystemDecline: true)),
      );
      expect(afterTimeout.pendingInterrupt!.fellowshipRequested, isFalse);

      // Defender now gets their own defense window and can still respond
      // deliberately (not a system decline).
      final prayerId = afterTimeout.players[1].hand.firstWhere((c) => c.defId == 'prayer').instanceId;
      final result = expectSuccess(
        applyAction(afterTimeout, DeclareDefense(playerId: 'p1', cardInstanceId: prayerId)),
      );
      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
    });

    test('a system decline for the defender lands the attack, same as a normal decline', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['goliaths_taunt'],
          1: ['prayer'],
        },
      );
      final pending = _openAttack(
        state,
        attackDefId: 'goliaths_taunt',
        attackerId: 'p0',
        defenderId: 'p1',
        targetArmor: ArmorType.helmet,
      );

      final result = expectSuccess(
        applyAction(pending, const DeclineDefense(playerId: 'p1', isSystemDecline: true)),
      );

      expect(result.pendingInterrupt, isNull);
      // Goliath's Taunt is a double hit: Strong straight to Lost.
      expect(result.players[1].armorOf(ArmorType.helmet).condition, ArmorCondition.lost);
    });

    test('a system decline is still rejected from a bystander who is not the defender or an eligible helper', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');

      // p0 is the attacker, never an eligible responder, system decline or not.
      final reason = expectFailure(
        applyAction(pending, const DeclineDefense(playerId: 'p0', isSystemDecline: true)),
      );
      expect(reason, contains('Only the defender'));
    });

    test('determinism: a system decline consumes no randomness and produces the same state as an equivalent scripted normal decline', () {
      final stateA = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final stateB = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );

      final pendingA = _openAttack(stateA, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final pendingB = _openAttack(stateB, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');

      final resultA = expectSuccess(
        applyAction(pendingA, const DeclineDefense(playerId: 'p1', isSystemDecline: true)),
      );
      final resultB = expectSuccess(
        applyAction(pendingB, const DeclineDefense(playerId: 'p1')),
      );

      // Same rngDrawCount (no randomness consumed by either path) and same
      // resulting armor condition; the only difference is the extra
      // DefenseTimedOut log entry on the system-decline side.
      expect(resultA.rngDrawCount, resultB.rngDrawCount);
      expect(
        resultA.players[1].armorOf(ArmorType.shield).condition,
        resultB.players[1].armorOf(ArmorType.shield).condition,
      );
      expect(resultA.eventLog.whereType<DefenseTimedOut>(), hasLength(1));
      expect(resultB.eventLog.whereType<DefenseTimedOut>(), isEmpty);
    });
  });
}
