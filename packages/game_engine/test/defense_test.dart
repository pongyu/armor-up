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
  group('Prayer blocks an attack', () {
    test('attack has no effect and card is discarded', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final prayerId = pending.players[1].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: prayerId)),
      );

      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
      expect(result.eventLog.whereType<AttackBlocked>(), hasLength(1));
      expect(result.discardPile.map((c) => c.defId), containsAll(['doubt', 'prayer']));
    });

    test('defender may decline and take the hit instead', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');

      final result = expectSuccess(applyAction(pending, const DeclineDefense(playerId: 'p1')));

      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.weakened);
    });

    test('only the defender may respond (not a bystander)', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['doubt'],
          1: ['prayer'],
          2: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final prayerId = pending.players[2].hand.first.instanceId;

      final reason = expectFailure(
        applyAction(pending, DeclareDefense(playerId: 'p2', cardInstanceId: prayerId)),
      );
      expect(reason, contains('Only the defender'));
    });
  });

  group('It Is Written reflects an attack', () {
    test('reflects a normal attack back at the attacker', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['it_is_written'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final iiwId = pending.players[1].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: iiwId)),
      );

      // p0 has no defense card, so the reflected hit lands immediately on them.
      expect(result.pendingInterrupt, isNull);
      expect(result.players[0].armorOf(ArmorType.shield).condition, ArmorCondition.weakened);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
      expect(result.eventLog.whereType<AttackReflected>(), hasLength(1));
    });

    test('reflected attack opens a new defense window if attacker holds a defense card', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt', 'prayer'],
          1: ['it_is_written'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final iiwId = pending.players[1].hand.first.instanceId;

      final afterReflect = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: iiwId)),
      );

      expect(afterReflect.pendingInterrupt, isNotNull);
      expect(afterReflect.pendingInterrupt!.attackerId, 'p1');
      expect(afterReflect.pendingInterrupt!.defenderId, 'p0');

      // Reflections chain: p0 (now defending) can reflect again.
      final prayerId = afterReflect.players[0].hand.firstWhere((c) => c.defId == 'prayer').instanceId;
      final blocked = expectSuccess(
        applyAction(afterReflect, DeclareDefense(playerId: 'p0', cardInstanceId: prayerId)),
      );
      expect(blocked.pendingInterrupt, isNull);
      expect(blocked.players[0].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
      expect(blocked.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
    });

    test('reflecting Goliath\'s Taunt keeps it a double hit on the original attacker', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['goliaths_taunt'],
          1: ['it_is_written'],
        },
      );
      final pending = _openAttack(
        state,
        attackDefId: 'goliaths_taunt',
        attackerId: 'p0',
        defenderId: 'p1',
        targetArmor: ArmorType.helmet,
      );
      final iiwId = pending.players[1].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: iiwId)),
      );

      expect(result.players[0].armorOf(ArmorType.helmet).condition, ArmorCondition.lost);
      expect(result.players[1].armorOf(ArmorType.helmet).condition, ArmorCondition.strong);
    });
  });

  group('Fellowship', () {
    test('a helper discarding a defense card blocks the attack', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['doubt'],
          1: ['fellowship'],
          2: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final fellowshipId = pending.players[1].hand.first.instanceId;

      final requested = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: fellowshipId)),
      );
      expect(requested.pendingInterrupt!.fellowshipRequested, isTrue);

      final helperCardId = requested.players[2].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(requested, DeclareDefense(playerId: 'p2', cardInstanceId: helperCardId)),
      );

      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
      expect(result.eventLog.whereType<AttackBlocked>().single.helperId, 'p2');
    });

    test('defender can still use their own Prayer if nobody helps', () {
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

      // The only other player declines to help.
      final afterDecline = expectSuccess(
        applyAction(requested, const DeclineDefense(playerId: 'p2')),
      );
      expect(afterDecline.pendingInterrupt!.fellowshipRequested, isFalse);

      // Defender now gets their own defense window.
      final prayerId = afterDecline.players[1].hand.firstWhere((c) => c.defId == 'prayer').instanceId;
      final result = expectSuccess(
        applyAction(afterDecline, DeclareDefense(playerId: 'p1', cardInstanceId: prayerId)),
      );

      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
    });

    test(
        'defender whose only defense card is Fellowship opens a helper '
        'request rather than resolving immediately', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['doubt'],
          1: ['fellowship'],
          2: ['prayer'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final fellowshipId = pending.players[1].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: fellowshipId)),
      );

      // Fellowship must open a helper request, not resolve the attack by
      // itself: the interrupt stays open, the request flag is set, and
      // the armor is untouched until someone actually helps or everyone
      // (including the defender) declines.
      expect(result.pendingInterrupt, isNotNull);
      expect(result.pendingInterrupt!.fellowshipRequested, isTrue);
      expect(result.pendingInterrupt!.defenderId, 'p1');
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.strong);
      expect(result.eventLog.whereType<AttackBlocked>(), isEmpty);
      // The card itself is discarded immediately (it was played), even
      // though the attack hasn't resolved yet.
      expect(result.discardPile.map((c) => c.defId), contains('fellowship'));
      expect(result.players[1].hand, isEmpty);
    });

    test(
        'in a 2-player game there is no eligible Fellowship helper, so the '
        'defender is the only one who can respond next', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['doubt'],
          1: ['fellowship'],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final fellowshipId = pending.players[1].hand.first.instanceId;

      final requested = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: fellowshipId)),
      );
      expect(requested.pendingInterrupt!.fellowshipRequested, isTrue);

      // The attacker is not a valid helper, so only the defender may act;
      // an attacker "declining to help" must be rejected.
      final rejected = expectFailure(
        applyAction(requested, const DeclineDefense(playerId: 'p0')),
      );
      expect(rejected, contains('Only the defender'));

      // With Fellowship already spent and no one else to ask, the
      // defender's only option left is to decline and take the hit.
      final result = expectSuccess(
        applyAction(requested, const DeclineDefense(playerId: 'p1')),
      );
      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.weakened);
    });

    test('attack lands if nobody helps and defender has no other defense card', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['doubt'],
          1: ['fellowship'],
          2: [],
        },
      );
      final pending = _openAttack(state, attackDefId: 'doubt', attackerId: 'p0', defenderId: 'p1');
      final fellowshipId = pending.players[1].hand.first.instanceId;

      final requested = expectSuccess(
        applyAction(pending, DeclareDefense(playerId: 'p1', cardInstanceId: fellowshipId)),
      );
      final afterDecline = expectSuccess(
        applyAction(requested, const DeclineDefense(playerId: 'p2')),
      );

      final result = expectSuccess(applyAction(afterDecline, const DeclineDefense(playerId: 'p1')));

      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.weakened);
    });
  });

  group('defense vs events', () {
    test('event cards resolve unconditionally with no defense window', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['jericho_march'],
          1: ['prayer'],
        },
        armorOverrides: {
          1: {ArmorType.shield: ArmorCondition.weakened},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      expect(result.pendingInterrupt, isNull);
      expect(result.players[1].armorOf(ArmorType.shield).condition, ArmorCondition.lost);
    });
  });
}
