import 'package:armor_up/state/filtered_state_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';

void main() {
  test('reconstructFromFiltered preserves the viewer\'s own hand exactly', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe', 'Sam'], seed: 7);
    final filtered = filterStateForPlayer(game, 'p1');

    final reconstructed = reconstructFromFiltered(filtered);

    final realP1 = game.playerById('p1');
    final reconstructedP1 = reconstructed.playerById('p1');
    expect(
      reconstructedP1.hand.map((c) => c.instanceId),
      realP1.hand.map((c) => c.instanceId),
    );
    expect(
      reconstructedP1.hand.map((c) => c.defId),
      realP1.hand.map((c) => c.defId),
    );
  });

  test(
    'reconstructFromFiltered replaces other players\' hands with placeholders '
    'that fail loudly if ever looked up as real cards',
    () {
      final game = newGame(playerNames: ['Mumu', 'Zoe', 'Sam'], seed: 7);
      final filtered = filterStateForPlayer(game, 'p1');

      final reconstructed = reconstructFromFiltered(filtered);

      for (final otherId in ['p0', 'p2']) {
        final real = game.playerById(otherId);
        final reconstructedOther = reconstructed.playerById(otherId);

        expect(reconstructedOther.hand.length, real.hand.length);
        for (final card in reconstructedOther.hand) {
          expect(card.defId, hiddenCardDefId);
          expect(() => cardDefById(card.defId), throwsA(anything));
        }
      }
    },
  );

  test('reconstructFromFiltered preserves public info and pile counts', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe'], seed: 3);
    final afterDraw = applyAction(game, const DrawCard(playerId: 'p0'));
    final state = (afterDraw as ActionSuccess).state;

    final filtered = filterStateForPlayer(state, 'p0');
    final reconstructed = reconstructFromFiltered(filtered);

    expect(reconstructed.turnNumber, state.turnNumber);
    expect(reconstructed.activePlayerIndex, state.activePlayerIndex);
    expect(reconstructed.hasDrawnThisTurn, state.hasDrawnThisTurn);
    expect(reconstructed.drawPile.length, state.drawPile.length);
    expect(reconstructed.discardPile.length, state.discardPile.length);
    for (var i = 0; i < state.players.length; i++) {
      expect(reconstructed.players[i].armor, state.players[i].armor);
      expect(reconstructed.players[i].wasEverDamaged, state.players[i].wasEverDamaged);
    }
  });
}
