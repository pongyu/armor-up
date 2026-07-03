// Runs N full games with random-legal-move bots and prints balance
// statistics: average game length in turns, win counts by winType, and
// play counts per card. Usage: dart run bin/simulate.dart [gameCount] [seed]
import 'dart:math';

import 'package:game_engine/game_engine.dart';

void main(List<String> args) {
  final gameCount = args.isNotEmpty ? int.parse(args[0]) : 200;
  final baseSeed = args.length > 1 ? int.parse(args[1]) : 12345;

  final turnCounts = <int>[];
  final winsByType = <WinType, int>{for (final t in WinType.values) t: 0};
  final playCountsByCardId = <String, int>{for (final d in deckDefinitions) d.id: 0};
  var incompleteGames = 0;

  for (var i = 0; i < gameCount; i++) {
    final playerCount = 2 + (i % 5); // cycle through 2..6 players
    final playerNames = List.generate(playerCount, (p) => 'Bot$p');
    final seed = baseSeed + i;

    final outcome = _runOneGame(
      playerNames: playerNames,
      seed: seed,
      playCountsByCardId: playCountsByCardId,
    );

    if (outcome == null) {
      incompleteGames++;
      continue;
    }

    turnCounts.add(outcome.turnNumber);
    winsByType[outcome.winner!.type] = winsByType[outcome.winner!.type]! + 1;
  }

  final completed = turnCounts.length;
  final avgTurns = completed == 0 ? 0.0 : turnCounts.reduce((a, b) => a + b) / completed;

  print('=== Armor Up! simulation: $gameCount games ($completed completed, $incompleteGames hit turn cap) ===');
  print('Average game length: ${avgTurns.toStringAsFixed(1)} turns');
  print('');
  print('Win counts by type:');
  for (final type in WinType.values) {
    print('  ${type.name}: ${winsByType[type]}');
  }
  print('');
  print('Play counts per card:');
  final sortedIds = playCountsByCardId.keys.toList()
    ..sort((a, b) => playCountsByCardId[b]!.compareTo(playCountsByCardId[a]!));
  for (final id in sortedIds) {
    final def = cardDefById(id);
    print('  ${def.name.padRight(20)} ${playCountsByCardId[id]}');
  }
}

/// Hard cap so a pathological bot loop (e.g. everyone always fasting)
/// cannot hang the simulation.
const int _maxTurnsPerGame = 500;

GameState? _runOneGame({
  required List<String> playerNames,
  required int seed,
  required Map<String, int> playCountsByCardId,
}) {
  final random = Random(seed);
  var state = newGame(playerNames: playerNames, seed: seed);

  while (!state.isGameOver && state.turnNumber <= _maxTurnsPerGame) {
    if (state.pendingInterrupt != null) {
      state = _resolveInterruptRandomly(state, random, playCountsByCardId);
      continue;
    }

    final activeId = state.activePlayer.id;

    if (!state.hasDrawnThisTurn) {
      state = _apply(state, DrawCard(playerId: activeId));
      continue;
    }

    if (!state.activePlayer.isFasting) {
      final played = _tryPlayRandomCard(state, random, playCountsByCardId);
      if (played != null) {
        state = played;
        continue;
      }
    }

    if (state.activePlayer.hand.length > maxHandSize) {
      final discardId = state.activePlayer.hand[random.nextInt(state.activePlayer.hand.length)].instanceId;
      state = _apply(state, DiscardCard(playerId: activeId, cardInstanceId: discardId));
      continue;
    }

    state = _apply(state, EndTurn(playerId: activeId));
  }

  return state.isGameOver ? state : null;
}

GameState _apply(GameState state, GameAction action) {
  final result = applyAction(state, action);
  if (result is ActionFailure) {
    throw StateError('Bot produced an illegal action $action: ${result.reason}');
  }
  return (result as ActionSuccess).state;
}

/// Attempts to play one uniformly-random legal (card, target) combination
/// from the active player's hand. Returns null if no legal play exists
/// (forcing the caller to fall through to discard/end-turn).
GameState? _tryPlayRandomCard(
  GameState state,
  Random random,
  Map<String, int> playCountsByCardId,
) {
  final player = state.activePlayer;
  final candidates = <PlayCard>[];

  for (final card in player.hand) {
    final def = cardDefById(card.defId);
    if (def.type == CardType.defense) continue;
    candidates.addAll(_legalPlaysFor(state, player.id, card, def));
  }

  if (candidates.isEmpty) return null;

  final chosen = candidates[random.nextInt(candidates.length)];
  final defId = cardDefById(
    player.hand.firstWhere((c) => c.instanceId == chosen.cardInstanceId).defId,
  ).id;
  final result = _apply(state, chosen);
  playCountsByCardId[defId] = (playCountsByCardId[defId] ?? 0) + 1;
  return result;
}

List<PlayCard> _legalPlaysFor(
  GameState state,
  String playerId,
  CardInstance card,
  CardDef def,
) {
  final others = state.players.where((p) => p.id != playerId && !p.isEliminated);

  switch (def.targetRule) {
    case TargetRule.specificArmorOnPlayer:
      return [
        for (final target in others)
          if (target.armorOf(def.fixedTarget!).condition != ArmorCondition.lost)
            PlayCard(playerId: playerId, cardInstanceId: card.instanceId, targetPlayerId: target.id),
      ];

    case TargetRule.anyPieceOnPlayer:
      return [
        for (final target in others)
          for (final piece in target.armor)
            if (piece.condition != ArmorCondition.lost)
              PlayCard(
                playerId: playerId,
                cardInstanceId: card.instanceId,
                targetPlayerId: target.id,
                targetArmor: piece.type,
              ),
      ];

    case TargetRule.singlePlayer:
      return [
        for (final target in others)
          if (target.hand.isNotEmpty)
            PlayCard(playerId: playerId, cardInstanceId: card.instanceId, targetPlayerId: target.id),
      ];

    case TargetRule.ownArmorPiece:
      final self = state.playerById(playerId);
      final requiredCondition =
          def.effect == EffectPrimitive.restoreOneStep ? ArmorCondition.weakened : ArmorCondition.lost;
      return [
        for (final piece in self.armor)
          if (piece.condition == requiredCondition)
            PlayCard(playerId: playerId, cardInstanceId: card.instanceId, targetArmor: piece.type),
      ];

    case TargetRule.allPlayers:
    case TargetRule.none:
      return [PlayCard(playerId: playerId, cardInstanceId: card.instanceId)];
  }
}

/// Resolves a pending defense interrupt with a random legal response:
/// the eligible responder (defender, or a helper during a Fellowship
/// request) randomly declares a defense card if they hold one, or
/// declines otherwise. Mirrors what a hotseat UI or network client would
/// let a human choose.
GameState _resolveInterruptRandomly(
  GameState state,
  Random random,
  Map<String, int> playCountsByCardId,
) {
  final pending = state.pendingInterrupt!;

  final String responderId;
  if (pending.fellowshipRequested) {
    final undecided = state.players.where(
      (p) => p.id != pending.defenderId && p.id != pending.attackerId && !p.isEliminated && !pending.helpersDeclined.contains(p.id),
    );
    responderId = undecided.isNotEmpty ? undecided.first.id : pending.defenderId;
  } else {
    responderId = pending.defenderId;
  }

  final responder = state.playerById(responderId);
  final defenseCards = responder.hand.where((c) => cardDefById(c.defId).type == CardType.defense).toList();

  // Decline if no defense card is held, or (to keep bot play varied for
  // balance testing) with 1-in-3 chance even when one is held.
  if (defenseCards.isEmpty || random.nextInt(3) == 0) {
    return _apply(state, DeclineDefense(playerId: responderId));
  }

  final chosen = defenseCards[random.nextInt(defenseCards.length)];
  playCountsByCardId[chosen.defId] = (playCountsByCardId[chosen.defId] ?? 0) + 1;
  return _apply(state, DeclareDefense(playerId: responderId, cardInstanceId: chosen.instanceId));
}
