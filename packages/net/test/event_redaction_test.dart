import 'dart:convert';

import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';
import 'package:test/test.dart';

void main() {
  group('CardStolen event visibility', () {
    test('CardStolen carries visibleTo restricted to the thief', () {
      const event = CardStolen(
        turnNumber: 1,
        thiefId: 'p0',
        victimId: 'p1',
        cardDefId: 'prayer',
      );
      expect(event.visibleTo, ['p0']);
    });

    test('CardStolen.redacted() strips cardDefId but keeps thief/victim', () {
      const event = CardStolen(
        turnNumber: 1,
        thiefId: 'p0',
        victimId: 'p1',
        cardDefId: 'prayer',
      );
      final redacted = event.redacted();
      expect(redacted.thiefId, 'p0');
      expect(redacted.victimId, 'p1');
      expect(redacted.turnNumber, 1);
    });

    test('every pre-existing event type is unrestricted (visibleTo null) and redacts to itself', () {
      final events = <GameEvent>[
        const CardPlayed(turnNumber: 1, playerId: 'p0', cardDefId: 'doubt'),
        const ArmorWeakened(turnNumber: 1, playerId: 'p0', armor: ArmorType.shield),
        const ArmorLost(turnNumber: 1, playerId: 'p0', armor: ArmorType.shield),
        const ArmorRestored(
          turnNumber: 1,
          playerId: 'p0',
          armor: ArmorType.shield,
          newCondition: ArmorCondition.strong,
        ),
        const AttackBlocked(turnNumber: 1, defenderId: 'p0', byCardDefId: 'prayer'),
        const AttackReflected(
          turnNumber: 1,
          originalAttackerId: 'p0',
          newDefenderId: 'p1',
          attackCardDefId: 'doubt',
        ),
        const TurnSkipped(turnNumber: 1, playerId: 'p0', reason: 'fasting'),
        const CardDrawn(turnNumber: 1, playerId: 'p0'),
        const CardDiscarded(turnNumber: 1, playerId: 'p0', cardDefId: 'doubt'),
        const DefenseTimedOut(turnNumber: 1, playerId: 'p0', wasHelper: false),
        const PlayerEliminated(turnNumber: 1, playerId: 'p0', cardsDiscarded: 2),
        const DeckReshuffled(turnNumber: 1),
        const GameEnded(turnNumber: 1, winnerId: 'p0', winType: WinType.elimination),
      ];
      for (final event in events) {
        expect(event.visibleTo, isNull, reason: '${event.runtimeType} should be public by default');
        expect(identical(event.redacted(), event), isTrue,
            reason: '${event.runtimeType} should redact to itself');
      }
    });
  });

  group('filterStateForPlayer event redaction', () {
    GameState stateWithStolenCard() {
      var state = newGame(playerNames: ['Mumu', 'Zoe', 'Sam'], seed: 1);
      state = state.appendEvent(
        const CardStolen(turnNumber: 1, thiefId: 'p0', victimId: 'p1', cardDefId: 'prayer'),
      );
      return state;
    }

    test('the thief receives the full CardStolen event', () {
      final state = stateWithStolenCard();
      final view = filterStateForPlayer(state, 'p0');
      final event = view.eventLog.whereType<CardStolen>().single;
      expect(event.cardDefId, 'prayer');
    });

    test('the victim receives the redacted form', () {
      final state = stateWithStolenCard();
      final view = filterStateForPlayer(state, 'p1');
      expect(view.eventLog.whereType<CardStolen>(), isEmpty);
      final redacted = view.eventLog.whereType<CardStolenRedacted>().single;
      expect(redacted.thiefId, 'p0');
      expect(redacted.victimId, 'p1');
    });

    test('a bystander (neither thief nor victim) also receives the redacted form', () {
      final state = stateWithStolenCard();
      final view = filterStateForPlayer(state, 'p2');
      expect(view.eventLog.whereType<CardStolen>(), isEmpty);
      expect(view.eventLog.whereType<CardStolenRedacted>(), hasLength(1));
    });

    test('event log length and ordering are identical across every viewer', () {
      final state = stateWithStolenCard();
      final thiefLog = filterStateForPlayer(state, 'p0').eventLog;
      final victimLog = filterStateForPlayer(state, 'p1').eventLog;
      final bystanderLog = filterStateForPlayer(state, 'p2').eventLog;

      expect(thiefLog.length, state.eventLog.length);
      expect(victimLog.length, state.eventLog.length);
      expect(bystanderLog.length, state.eventLog.length);
      for (var i = 0; i < state.eventLog.length; i++) {
        expect(thiefLog[i].turnNumber, state.eventLog[i].turnNumber);
        expect(victimLog[i].turnNumber, state.eventLog[i].turnNumber);
        expect(bystanderLog[i].turnNumber, state.eventLog[i].turnNumber);
      }
    });

    test('pre-existing public events remain visible to every viewer unchanged', () {
      final state = newGame(playerNames: ['Mumu', 'Zoe'], seed: 1).appendEvent(
        const CardPlayed(turnNumber: 1, playerId: 'p0', cardDefId: 'doubt', targetPlayerId: 'p1'),
      );
      final p0View = filterStateForPlayer(state, 'p0');
      final p1View = filterStateForPlayer(state, 'p1');

      final p0Event = p0View.eventLog.whereType<CardPlayed>().single;
      final p1Event = p1View.eventLog.whereType<CardPlayed>().single;
      expect(p0Event.cardDefId, 'doubt');
      expect(p1Event.cardDefId, 'doubt');
    });
  });

  group('JSON round-trip', () {
    test('CardStolen round-trips through JSON', () {
      const event = CardStolen(turnNumber: 3, thiefId: 'p0', victimId: 'p1', cardDefId: 'renewal');
      final decoded = gameEventFromJson(jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>);
      expect(decoded, isA<CardStolen>());
      final c = decoded as CardStolen;
      expect(c.thiefId, 'p0');
      expect(c.victimId, 'p1');
      expect(c.cardDefId, 'renewal');
      expect(c.turnNumber, 3);
    });

    test('CardStolenRedacted round-trips through JSON', () {
      const event = CardStolenRedacted(turnNumber: 3, thiefId: 'p0', victimId: 'p1');
      final decoded = gameEventFromJson(jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>);
      expect(decoded, isA<CardStolenRedacted>());
      final c = decoded as CardStolenRedacted;
      expect(c.thiefId, 'p0');
      expect(c.victimId, 'p1');
      expect(c.turnNumber, 3);
      // The redacted wire form never carries a cardDefId key at all.
      expect(jsonDecode(jsonEncode(event.toJson())), isNot(contains('cardDefId')));
    });

    test('FilteredGameState containing a redacted CardStolenRedacted round-trips end to end', () {
      var state = newGame(playerNames: ['Mumu', 'Zoe', 'Sam'], seed: 1);
      state = state.appendEvent(
        const CardStolen(turnNumber: 1, thiefId: 'p0', victimId: 'p1', cardDefId: 'prayer'),
      );
      final view = filterStateForPlayer(state, 'p1');
      final decoded = FilteredGameState.fromJson(
        jsonDecode(jsonEncode(view.toJson())) as Map<String, dynamic>,
      );
      final redacted = decoded.eventLog.whereType<CardStolenRedacted>().single;
      expect(redacted.thiefId, 'p0');
      expect(redacted.victimId, 'p1');
      expect(decoded.eventLog.whereType<CardStolen>(), isEmpty);
    });
  });
}
