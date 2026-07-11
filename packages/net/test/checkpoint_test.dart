import 'dart:convert';

import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';
import 'package:test/test.dart';

void main() {
  test('GameAction round-trips through JSON', () {
    const action = PlayCard(
      playerId: 'p0',
      cardInstanceId: 'c12',
      targetPlayerId: 'p1',
      targetArmor: ArmorType.shield,
    );
    final json = action.toJson();
    final decoded = gameActionFromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

    expect(decoded, isA<PlayCard>());
    final replayed = decoded as PlayCard;
    expect(replayed.playerId, 'p0');
    expect(replayed.cardInstanceId, 'c12');
    expect(replayed.targetPlayerId, 'p1');
    expect(replayed.targetArmor, ArmorType.shield);
  });

  test('filterStateForPlayer never leaks another player\'s hand', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe'], seed: 42);

    final viewOfP0 = filterStateForPlayer(game, 'p0');
    final json = jsonDecode(jsonEncode(viewOfP0.toJson())) as Map<String, dynamic>;

    final p0View = (json['players'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['id'] == 'p0');
    final p1View = (json['players'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['id'] == 'p1');

    // Viewer sees their own hand in full.
    expect(p0View['hand'], isNotNull);
    expect((p0View['hand'] as List).length, game.playerById('p0').hand.length);

    // Viewer never sees another player's hand contents, only its size.
    expect(p1View.containsKey('hand'), isFalse);
    expect(p1View['handSize'], game.playerById('p1').hand.length);

    // Draw pile is a count, not the actual cards (order/identity would
    // otherwise leak future draws).
    expect(json.containsKey('drawPile'), isFalse);
    expect(json['drawPileCount'], game.drawPile.length);
  });

  test('FilteredGameState round-trips through JSON', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe', 'Sam'], seed: 7);
    final view = filterStateForPlayer(game, 'p1');
    final decoded = FilteredGameState.fromJson(
      jsonDecode(jsonEncode(view.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.viewerId, 'p1');
    expect(decoded.players.length, 3);
    expect(
      decoded.players.firstWhere((p) => p.id == 'p1').hand?.length,
      game.playerById('p1').hand.length,
    );
    expect(decoded.players.firstWhere((p) => p.id == 'p0').hand, isNull);
  });
}
