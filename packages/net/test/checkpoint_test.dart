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

  test('PlayerState.wasEverBroken round-trips through JSON', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe'], seed: 7);
    final broken = game.updatePlayer(
      'p0',
      (p) => p.withArmorCondition(ArmorType.helmet, ArmorCondition.lost),
    );
    expect(broken.playerById('p0').wasEverBroken, isTrue);

    final json = jsonEncode(broken.playerById('p0').toJson());
    final decoded = PlayerStateJson.fromJson(jsonDecode(json) as Map<String, dynamic>);

    expect(decoded.wasEverBroken, isTrue);
  });

  test('GameState.restorationWinEnabled and maxReshuffles round-trip through JSON', () {
    final game = newGame(
      playerNames: ['Mumu', 'Zoe'],
      seed: 7,
      restorationWinEnabled: false,
      maxReshuffles: 3,
    );

    final json = jsonEncode(game.toJson());
    final decoded = GameStateJson.fromJson(jsonDecode(json) as Map<String, dynamic>);

    expect(decoded.restorationWinEnabled, isFalse);
    expect(decoded.maxReshuffles, 3);
  });

  test('GameState.maxReshuffles round-trips as null when unset (unlimited reshuffles)', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe'], seed: 7);
    expect(game.maxReshuffles, isNull);

    final json = jsonEncode(game.toJson());
    final decoded = GameStateJson.fromJson(jsonDecode(json) as Map<String, dynamic>);

    expect(decoded.maxReshuffles, isNull);
    expect(decoded.restorationWinEnabled, isTrue);
  });

  test('FilteredGameState.restorationWinEnabled and maxReshuffles round-trip through JSON', () {
    final game = newGame(
      playerNames: ['Mumu', 'Zoe'],
      seed: 7,
      restorationWinEnabled: false,
      maxReshuffles: 1,
    );
    final view = filterStateForPlayer(game, 'p0');
    final decoded = FilteredGameState.fromJson(
      jsonDecode(jsonEncode(view.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.restorationWinEnabled, isFalse);
    expect(decoded.maxReshuffles, 1);
  });

  test('PlayerState.fastingRestoreTarget round-trips through JSON, including the unset (null) case', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe'], seed: 7);
    final fasting = game.updatePlayer(
      'p0',
      (p) => p.copyWith(fastingScheduled: true, fastingRestoreTarget: ArmorType.helmet),
    );

    final json = jsonEncode(fasting.playerById('p0').toJson());
    final decoded = PlayerStateJson.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(decoded.fastingRestoreTarget, ArmorType.helmet);

    // Unset case: never present in the JSON at all, not just null.
    final rawJson = jsonDecode(json) as Map<String, dynamic>;
    final unfasting = game.playerById('p0');
    final unsetRawJson = jsonDecode(jsonEncode(unfasting.toJson())) as Map<String, dynamic>;
    expect(rawJson.containsKey('fastingRestoreTarget'), isTrue);
    expect(unsetRawJson.containsKey('fastingRestoreTarget'), isFalse);
    final decodedUnset = PlayerStateJson.fromJson(unsetRawJson);
    expect(decodedUnset.fastingRestoreTarget, isNull);
  });

  test('fastingRestoreTarget is visible to every viewer via FilteredGameState (public, not redacted)', () {
    final game = newGame(playerNames: ['Mumu', 'Zoe'], seed: 7);
    final fasting = game.updatePlayer(
      'p0',
      (p) => p.copyWith(fastingScheduled: true, fastingRestoreTarget: ArmorType.helmet),
    );

    // p1 viewing p0's fastingRestoreTarget - not p0's own hand, so this
    // must come through even though p1 never sees p0's hand contents.
    final viewFromP1 = filterStateForPlayer(fasting, 'p1');
    final p0View = viewFromP1.players.firstWhere((p) => p.id == 'p0');
    expect(p0View.fastingRestoreTarget, ArmorType.helmet);
    expect(p0View.hand, isNull); // hand still redacted, unlike the target
  });

  test('RestorationImminent round-trips through JSON', () {
    var state = newGame(playerNames: ['Mumu', 'Zoe'], seed: 7);
    state = state.appendEvent(const RestorationImminent(turnNumber: 4, playerId: 'p0'));

    final decoded = GameStateJson.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
    );
    final event = decoded.eventLog.whereType<RestorationImminent>().single;
    expect(event.turnNumber, 4);
    expect(event.playerId, 'p0');
  });
}
