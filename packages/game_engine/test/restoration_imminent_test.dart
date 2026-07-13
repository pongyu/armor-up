import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('RestorationImminent announcement', () {
    test('emitted on the false-to-true transition into isFullyRestored', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      );
      expect(state.players[0].isFullyRestored, isFalse);

      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      expect(result.players[0].isFullyRestored, isTrue);
      final events = result.eventLog.whereType<RestorationImminent>();
      expect(events, hasLength(1));
      expect(events.single.playerId, 'p0');
    });

    test('not re-emitted on subsequent actions while it continues to hold', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
        drawPileDefIds: ['prayer'],
      );
      final cardId = state.players[0].hand.first.instanceId;
      state = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );
      expect(state.eventLog.whereType<RestorationImminent>(), hasLength(1));

      // Alice is still fully restored; further unrelated actions (discard
      // down to the hand limit isn't needed here, so just draw for the
      // sake of taking another action) must not emit a second
      // announcement while the condition merely continues to hold.
      state = state.copyWith(hasDrawnThisTurn: false);
      state = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));
      expect(state.players[0].isFullyRestored, isTrue);
      expect(state.eventLog.whereType<RestorationImminent>(), hasLength(1));
    });

    test('re-emitted after being knocked below full and later re-achieving it (transition-based, not level-based)', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer', 'renewal'],
          1: ['fiery_dart'],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      );

      // First transition into fully restored.
      final armorBearerId = state.players[0].hand.firstWhere((c) => c.defId == 'armor_bearer').instanceId;
      state = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: armorBearerId, targetArmor: ArmorType.helmet),
        ),
      );
      expect(state.players[0].isFullyRestored, isTrue);
      expect(state.eventLog.whereType<RestorationImminent>(), hasLength(1));

      state = expectSuccess(applyAction(state, const EndTurn(playerId: 'p0')));

      // Bob knocks her back below full.
      state = expectSuccess(applyAction(state, const DrawCard(playerId: 'p1')));
      final fieryDartId = state.players[1].hand.firstWhere((c) => c.defId == 'fiery_dart').instanceId;
      state = expectSuccess(
        applyAction(
          state,
          PlayCard(
            playerId: 'p1',
            cardInstanceId: fieryDartId,
            targetPlayerId: 'p0',
            targetArmor: ArmorType.sword,
          ),
        ),
      );
      expect(state.players[0].isFullyRestored, isFalse);
      state = expectSuccess(applyAction(state, const EndTurn(playerId: 'p1')));

      // Alice restores the piece again with Renewal - a second, genuine
      // transition back into fully restored.
      state = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));
      final renewalId = state.players[0].hand.firstWhere((c) => c.defId == 'renewal').instanceId;
      state = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: renewalId, targetArmor: ArmorType.sword),
        ),
      );

      expect(state.players[0].isFullyRestored, isTrue);
      expect(state.eventLog.whereType<RestorationImminent>(), hasLength(2));
      expect(
        state.eventLog.whereType<RestorationImminent>().map((e) => e.playerId),
        ['p0', 'p0'],
      );
    });

    test('never emitted when restorationWinEnabled is false (basic mode)', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      ).copyWith(restorationWinEnabled: false);

      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      expect(result.players[0].isFullyRestored, isTrue);
      expect(result.eventLog.whereType<RestorationImminent>(), isEmpty);
    });

    test('emitted on the transition triggered by Fasting completing (not on play, per the delayed-restore timing)', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fasting'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
        drawPileDefIds: ['prayer', 'prayer'],
      );

      final fastingId = state.players[0].hand.first.instanceId;
      state = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: fastingId, targetArmor: ArmorType.helmet),
        ),
      );
      // Not fully restored yet - the fast hasn't been endured.
      expect(state.players[0].isFullyRestored, isFalse);
      expect(state.eventLog.whereType<RestorationImminent>(), isEmpty);

      state = expectSuccess(applyAction(state, const EndTurn(playerId: 'p0')));
      state = expectSuccess(applyAction(state, const DrawCard(playerId: 'p1')));
      state = expectSuccess(applyAction(state, const EndTurn(playerId: 'p1')));
      state = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));

      // Ending the fasted turn completes the fast and triggers the
      // transition - this is where the announcement must fire.
      state = expectSuccess(applyAction(state, const EndTurn(playerId: 'p0')));
      expect(state.players[0].isFullyRestored, isTrue);
      expect(state.eventLog.whereType<RestorationImminent>(), hasLength(1));
      expect(state.eventLog.whereType<RestorationImminent>().single.playerId, 'p0');
    });

    test('JSON round-trip (net package covers full serialization; this checks the event carries the right data)', () {
      const event = RestorationImminent(turnNumber: 5, playerId: 'p0');
      expect(event.turnNumber, 5);
      expect(event.playerId, 'p0');
      expect(event.visibleTo, isNull); // public
    });
  });
}
