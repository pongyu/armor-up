import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';

import 'package:armor_up/widgets/event_log_widget.dart';

void main() {
  GameState twoPlayerState() => newGame(playerNames: ['Alice', 'Bob'], seed: 1);

  group('describeEvent: CardStolen redaction', () {
    test('a full CardStolen (as held by the engine on hotseat) renders redacted text, not the card name', () {
      final state = twoPlayerState();
      const event = CardStolen(turnNumber: 1, thiefId: 'p0', victimId: 'p1', cardDefId: 'prayer');

      final text = describeEvent(event, state);

      expect(text, 'Alice stole a card from Bob');
      expect(text, isNot(contains('Prayer')));
    });

    test('a CardStolenRedacted (as received by a non-thief LAN client) renders identical text', () {
      final state = twoPlayerState();
      const event = CardStolenRedacted(turnNumber: 1, thiefId: 'p0', victimId: 'p1');

      final text = describeEvent(event, state);

      expect(text, 'Alice stole a card from Bob');
    });
  });

  group('describeEvent: regression - pre-existing events remain visible to everyone', () {
    test('CardPlayed still names the card', () {
      final state = twoPlayerState();
      const event = CardPlayed(
        turnNumber: 1,
        playerId: 'p0',
        cardDefId: 'doubt',
        targetPlayerId: 'p1',
      );
      expect(describeEvent(event, state), 'Alice played Doubt on Bob');
    });

    test('ArmorLost still names the piece', () {
      final state = twoPlayerState();
      const event = ArmorLost(turnNumber: 1, playerId: 'p1', armor: ArmorType.shield);
      expect(describeEvent(event, state), "Bob's Shield of Faith was lost");
    });

    test('PlayerEliminated still names the player', () {
      final state = twoPlayerState();
      const event = PlayerEliminated(turnNumber: 1, playerId: 'p1', cardsDiscarded: 3);
      expect(describeEvent(event, state), 'Bob was eliminated');
    });

    test('DefenseTimedOut still names the player', () {
      final state = twoPlayerState();
      const event = DefenseTimedOut(turnNumber: 1, playerId: 'p1', wasHelper: false);
      expect(describeEvent(event, state), 'Bob ran out of time to respond');
    });
  });
}
