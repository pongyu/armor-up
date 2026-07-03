import 'package:game_engine/game_engine.dart';

/// Builds a [GameState] with explicit hands and armor, bypassing the
/// normal shuffle-and-deal in [newGame], so tests can set up exact
/// scenarios (e.g. "player 0 holds exactly one Doubt and one Prayer").
///
/// [hands] maps player index to a list of card def ids; each becomes a
/// [CardInstance] with a synthetic instance id. Remaining deck cards (not
/// dealt to any hand) form the draw pile, in [deckDefinitions] order
/// (deterministic, not shuffled) unless [drawPileDefIds] is given
/// explicitly.
GameState buildTestState({
  required List<String> playerNames,
  required Map<int, List<String>> hands,
  List<String>? drawPileDefIds,
  Map<int, Map<ArmorType, ArmorCondition>>? armorOverrides,
  int seed = 1,
}) {
  var counter = 0;
  String nextId() => 't${counter++}';

  final players = <PlayerState>[];
  for (var i = 0; i < playerNames.length; i++) {
    final defIds = hands[i] ?? const [];
    final hand = [
      for (final defId in defIds) CardInstance(instanceId: nextId(), defId: defId),
    ];

    var armor = startingArmorSet();
    final overrides = armorOverrides?[i];
    var wasEverDamaged = false;
    if (overrides != null) {
      armor = [
        for (final piece in armor)
          if (overrides.containsKey(piece.type))
            piece.copyWith(condition: overrides[piece.type])
          else
            piece,
      ];
      wasEverDamaged = overrides.values.any((c) => c != ArmorCondition.strong);
    }

    players.add(
      PlayerState(
        id: 'p$i',
        name: playerNames[i],
        armor: armor,
        hand: hand,
        wasEverDamaged: wasEverDamaged,
      ),
    );
  }

  final drawPile = [
    for (final defId in drawPileDefIds ?? const []) CardInstance(instanceId: nextId(), defId: defId),
  ];

  return GameState(
    players: players,
    activePlayerIndex: 0,
    drawPile: drawPile,
    discardPile: const [],
    rngSeed: seed,
    nextInstanceId: counter,
    hasDrawnThisTurn: true,
  );
}

GameState expectSuccess(ActionResult result) {
  if (result is ActionFailure) {
    throw StateError('Expected ActionSuccess but got failure: ${result.reason}');
  }
  return (result as ActionSuccess).state;
}

String expectFailure(ActionResult result) {
  if (result is ActionSuccess) {
    throw StateError('Expected ActionFailure but got success: ${result.state}');
  }
  return (result as ActionFailure).reason;
}
