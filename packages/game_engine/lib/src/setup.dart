import 'deck.dart';
import 'models/armor.dart';
import 'models/card.dart';
import 'models/game_state.dart';
import 'models/player.dart';
import 'rng.dart';

const int startingHandSize = 5;
const int minPlayers = 2;
const int maxPlayers = 6;

/// Builds a fresh, shuffled [GameState] for [playerNames] (2-6 players),
/// each starting with a full set of Strong armor and a 5-card hand, dealt
/// deterministically from [seed].
GameState newGame({
  required List<String> playerNames,
  required int seed,
}) {
  if (playerNames.length < minPlayers || playerNames.length > maxPlayers) {
    throw ArgumentError.value(
      playerNames.length,
      'playerNames.length',
      'Must be between $minPlayers and $maxPlayers players',
    );
  }

  final random = GameRandom(seed: seed, drawCount: 0);

  var instanceCounter = 0;
  final allCards = <CardInstance>[];
  for (final def in deckDefinitions) {
    for (var i = 0; i < def.countInDeck; i++) {
      allCards.add(
        CardInstance(instanceId: 'c${instanceCounter++}', defId: def.id),
      );
    }
  }

  final shuffled = random.shuffled(allCards);
  final drawPile = [...shuffled];

  final players = <PlayerState>[];
  for (var i = 0; i < playerNames.length; i++) {
    final hand = drawPile.take(startingHandSize).toList();
    drawPile.removeRange(0, startingHandSize);
    players.add(
      PlayerState(
        id: 'p$i',
        name: playerNames[i],
        armor: startingArmorSet(),
        hand: hand,
      ),
    );
  }

  return GameState(
    players: players,
    activePlayerIndex: 0,
    drawPile: drawPile,
    discardPile: const [],
    rngSeed: seed,
    rngDrawCount: random.drawCount,
    nextInstanceId: instanceCounter,
    turnNumber: 1,
  );
}
