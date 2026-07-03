import 'action_result.dart';
import 'actions/game_action.dart';
import 'deck.dart';
import 'effects.dart';
import 'models/armor.dart';
import 'models/card.dart';
import 'models/game_event.dart';
import 'models/game_state.dart';
import 'models/win_result.dart';
import 'rng.dart';

export 'action_result.dart';
export 'actions/game_action.dart';
export 'deck.dart';
export 'models/armor.dart';
export 'models/card.dart';
export 'models/game_event.dart';
export 'models/game_state.dart';
export 'models/pending_interrupt.dart';
export 'models/player.dart';
export 'models/win_result.dart';
export 'setup.dart';

const int maxHandSize = 5;

/// The single entry point for all player input. Validates [action] against
/// [state]'s current rules (whose turn it is, whether an interrupt is
/// pending, whether the card is in hand, target legality, etc.) and, if
/// legal, returns the resulting [GameState] wrapped in [ActionSuccess].
/// Illegal input returns [ActionFailure] with a human-readable reason and
/// never mutates or throws for rule violations.
ActionResult applyAction(GameState state, GameAction action) {
  if (state.isGameOver) {
    return const ActionFailure('Game has already ended');
  }

  if (state.pendingInterrupt != null) {
    return switch (action) {
      DeclareDefense() => _declareDefense(state, action),
      DeclineDefense() => _declineDefense(state, action),
      _ => const ActionFailure(
          'An attack is awaiting a defense response; only DeclareDefense '
          'or DeclineDefense are valid right now',
        ),
    };
  }

  return switch (action) {
    DrawCard() => _drawCard(state, action),
    PlayCard() => _playCard(state, action),
    DiscardCard() => _discardCard(state, action),
    EndTurn() => _endTurn(state, action),
    DeclareDefense() => const ActionFailure('No attack is pending'),
    DeclineDefense() => const ActionFailure('No attack is pending'),
  };
}

bool _isActivePlayer(GameState state, String playerId) =>
    state.activePlayer.id == playerId;

// ---------------------------------------------------------------------------
// Draw
// ---------------------------------------------------------------------------

ActionResult _drawCard(GameState state, DrawCard action) {
  if (!_isActivePlayer(state, action.playerId)) {
    return const ActionFailure('Only the active player may draw');
  }
  if (state.hasDrawnThisTurn) {
    return const ActionFailure('Already drew a card this turn');
  }

  final (drawn, nextState) = _drawOne(state, action.playerId);
  if (drawn == null) {
    // Both piles empty; nothing to draw. Not an error - just proceed.
    return ActionSuccess(nextState.copyWith(hasDrawnThisTurn: true));
  }

  return ActionSuccess(nextState.copyWith(hasDrawnThisTurn: true));
}

/// Draws one card for [playerId] from the draw pile, reshuffling the
/// discard pile into a fresh draw pile first if it is empty. Returns the
/// drawn instance (or null if both piles are empty) and the updated state.
(CardInstance?, GameState) _drawOne(GameState state, String playerId) {
  var working = state;

  if (working.drawPile.isEmpty) {
    if (working.discardPile.isEmpty) {
      return (null, working);
    }
    final random = GameRandom(
      seed: working.rngSeed,
      drawCount: working.rngDrawCount,
    );
    final reshuffled = random.shuffled(working.discardPile);
    working = working.copyWith(
      drawPile: reshuffled,
      discardPile: const [],
      rngDrawCount: random.drawCount,
    );
    working = working.appendEvent(
      DeckReshuffled(turnNumber: working.turnNumber),
    );
  }

  final card = working.drawPile.first;
  final remainingDraw = working.drawPile.skip(1).toList();
  working = working.copyWith(drawPile: remainingDraw);
  working = working.updatePlayer(
    playerId,
    (p) => p.copyWith(hand: [...p.hand, card]),
  );
  working = working.appendEvent(
    CardDrawn(turnNumber: working.turnNumber, playerId: playerId),
  );
  return (card, working);
}

// ---------------------------------------------------------------------------
// Play
// ---------------------------------------------------------------------------

ActionResult _playCard(GameState state, PlayCard action) {
  if (!_isActivePlayer(state, action.playerId)) {
    return const ActionFailure('Only the active player may play a card');
  }
  if (!state.hasDrawnThisTurn) {
    return const ActionFailure('Must draw before playing a card');
  }
  if (state.hasPlayedCardThisTurn) {
    return const ActionFailure('Already played a card this turn');
  }

  final player = state.activePlayer;
  if (player.isFasting) {
    return const ActionFailure(
      'This player is fasting and must skip their play step this turn',
    );
  }

  final cardInstance = player.hand
      .where((c) => c.instanceId == action.cardInstanceId)
      .firstOrNull;
  if (cardInstance == null) {
    return const ActionFailure('Card is not in the active player\'s hand');
  }
  final def = cardDefById(cardInstance.defId);

  if (def.type == CardType.defense) {
    return const ActionFailure(
      'Defense cards can only be played in response to an attack',
    );
  }

  final targetError = _validateTarget(state, def, action);
  if (targetError != null) {
    return ActionFailure(targetError);
  }

  // The played card goes to the discard pile immediately, even for
  // attacks that open a defense window; PendingAttack tracks the card by
  // defId for reflection/logging rather than moving it back out again.
  var working = state.updatePlayer(
    player.id,
    (p) => p.copyWith(
      hand: p.hand.where((c) => c.instanceId != cardInstance.instanceId).toList(),
    ),
  );
  working = working.copyWith(
    discardPile: [...working.discardPile, cardInstance],
    hasPlayedCardThisTurn: true,
  );
  working = working.appendEvent(
    CardPlayed(
      turnNumber: working.turnNumber,
      playerId: player.id,
      cardDefId: def.id,
      targetPlayerId: action.targetPlayerId,
      targetArmor: action.targetArmor,
    ),
  );

  final result = resolveEffect(
    state: working,
    def: def,
    action: action,
  );
  return ActionSuccess(_checkEliminationWin(result));
}

String? _validateTarget(GameState state, CardDef def, PlayCard action) {
  switch (def.targetRule) {
    case TargetRule.specificArmorOnPlayer:
      if (action.targetPlayerId == null) {
        return 'This card requires a target player';
      }
      if (action.targetPlayerId == action.playerId) {
        return 'Cannot target yourself with an attack';
      }
      if (state.indexOfPlayer(action.targetPlayerId!) == -1) {
        return 'Unknown target player';
      }
      final target = state.playerById(action.targetPlayerId!);
      if (target.isEliminated) {
        return 'Target player is already eliminated';
      }
      final armorType = def.fixedTarget!;
      if (target.armorOf(armorType).condition == ArmorCondition.lost) {
        return 'Target armor piece is already lost';
      }
    case TargetRule.anyPieceOnPlayer:
      if (action.targetPlayerId == null) {
        return 'This card requires a target player';
      }
      if (action.targetPlayerId == action.playerId) {
        return 'Cannot target yourself with an attack';
      }
      if (state.indexOfPlayer(action.targetPlayerId!) == -1) {
        return 'Unknown target player';
      }
      if (action.targetArmor == null) {
        return 'This card requires a target armor piece';
      }
      final target = state.playerById(action.targetPlayerId!);
      if (target.isEliminated) {
        return 'Target player is already eliminated';
      }
      if (target.armorOf(action.targetArmor!).condition ==
          ArmorCondition.lost) {
        return 'Target armor piece is already lost';
      }
    case TargetRule.singlePlayer:
      if (action.targetPlayerId == null) {
        return 'This card requires a target player';
      }
      if (action.targetPlayerId == action.playerId) {
        return 'Cannot target yourself';
      }
      if (state.indexOfPlayer(action.targetPlayerId!) == -1) {
        return 'Unknown target player';
      }
      final target = state.playerById(action.targetPlayerId!);
      if (target.hand.isEmpty) {
        return 'Target player has no cards to steal';
      }
    case TargetRule.ownArmorPiece:
      if (action.targetArmor == null) {
        return 'This card requires a target armor piece of your own';
      }
      final self = state.playerById(action.playerId);
      final piece = self.armorOf(action.targetArmor!);
      final def = cardDefById(
        self.hand
                .where((c) => c.instanceId == action.cardInstanceId)
                .firstOrNull
                ?.defId ??
            '',
      );
      final requiredCondition = def.effect == EffectPrimitive.restoreOneStep
          ? ArmorCondition.weakened
          : ArmorCondition.lost;
      if (piece.condition != requiredCondition) {
        return 'Target armor piece is not in the right condition for this card';
      }
    case TargetRule.allPlayers:
    case TargetRule.none:
      break;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Discard
// ---------------------------------------------------------------------------

ActionResult _discardCard(GameState state, DiscardCard action) {
  final player = state.playerById(action.playerId);
  final cardInstance =
      player.hand.where((c) => c.instanceId == action.cardInstanceId).firstOrNull;
  if (cardInstance == null) {
    return const ActionFailure('Card is not in that player\'s hand');
  }

  var working = state.updatePlayer(
    action.playerId,
    (p) => p.copyWith(
      hand: p.hand.where((c) => c.instanceId != cardInstance.instanceId).toList(),
    ),
  );
  working = working.copyWith(discardPile: [...working.discardPile, cardInstance]);
  working = working.appendEvent(
    CardDiscarded(
      turnNumber: working.turnNumber,
      playerId: action.playerId,
      cardDefId: cardInstance.defId,
    ),
  );
  return ActionSuccess(working);
}

// ---------------------------------------------------------------------------
// End turn
// ---------------------------------------------------------------------------

ActionResult _endTurn(GameState state, EndTurn action) {
  if (!_isActivePlayer(state, action.playerId)) {
    return const ActionFailure('Only the active player may end their turn');
  }
  if (!state.hasDrawnThisTurn) {
    return const ActionFailure('Must draw before ending the turn');
  }
  final player = state.activePlayer;
  if (player.hand.length > maxHandSize) {
    return const ActionFailure(
      'Must discard down to the hand limit before ending the turn',
    );
  }

  // The outgoing player's own skipped-turn flag (if any) is now over.
  var working = state;
  if (player.isFasting) {
    working = working.updatePlayer(player.id, (p) => p.copyWith(isFasting: false));
  }

  final nextIndex = (working.activePlayerIndex + 1) % working.players.length;
  working = working.copyWith(
    activePlayerIndex: nextIndex,
    hasDrawnThisTurn: false,
    hasPlayedCardThisTurn: false,
    turnNumber: working.turnNumber + 1,
  );

  // If the incoming player scheduled a Fasting skip on an earlier turn,
  // this is the turn it applies to: convert the schedule into an active
  // skip and log it now (they will still draw normally; only PlayCard is
  // blocked for them this turn).
  final incoming = working.players[nextIndex];
  if (incoming.fastingScheduled) {
    working = working.updatePlayer(
      incoming.id,
      (p) => p.copyWith(isFasting: true, fastingScheduled: false),
    );
    working = working.appendEvent(
      TurnSkipped(
        turnNumber: working.turnNumber,
        playerId: incoming.id,
        reason: 'fasting',
      ),
    );
  }

  return ActionSuccess(_checkRestorationWin(_checkEliminationWin(working)));
}

// ---------------------------------------------------------------------------
// Defense interrupt responses
// ---------------------------------------------------------------------------

ActionResult _declareDefense(GameState state, DeclareDefense action) {
  final pending = state.pendingInterrupt!;
  final isDefender = action.playerId == pending.defenderId;
  final isAttacker = action.playerId == pending.attackerId;
  final isHelper = pending.fellowshipRequested && !isDefender && !isAttacker;

  if (!isDefender && !isHelper) {
    return const ActionFailure(
      'Only the defender (or, during a Fellowship request, another '
      'player) may declare a defense right now',
    );
  }

  final responder = state.playerById(action.playerId);
  final cardInstance = responder.hand
      .where((c) => c.instanceId == action.cardInstanceId)
      .firstOrNull;
  if (cardInstance == null) {
    return const ActionFailure('Card is not in that player\'s hand');
  }
  final def = cardDefById(cardInstance.defId);
  if (def.type != CardType.defense) {
    return const ActionFailure('That is not a defense card');
  }

  var working = state.updatePlayer(
    action.playerId,
    (p) => p.copyWith(
      hand: p.hand.where((c) => c.instanceId != cardInstance.instanceId).toList(),
    ),
  );
  working = working.copyWith(discardPile: [...working.discardPile, cardInstance]);

  final result = resolveDefense(
    state: working,
    def: def,
    responderId: action.playerId,
    isHelper: isHelper,
  );
  return ActionSuccess(_checkEliminationWin(result));
}

ActionResult _declineDefense(GameState state, DeclineDefense action) {
  final pending = state.pendingInterrupt!;
  final isDefender = action.playerId == pending.defenderId;
  final isAttacker = action.playerId == pending.attackerId;
  final isHelper = pending.fellowshipRequested && !isDefender && !isAttacker;

  if (!isDefender && !isHelper) {
    return const ActionFailure(
      'Only the defender (or, during a Fellowship request, another '
      'player) may decline right now',
    );
  }

  if (isHelper) {
    if (pending.helpersDeclined.contains(action.playerId)) {
      return const ActionFailure('This player has already declined to help');
    }
    final declined = {...pending.helpersDeclined, action.playerId};
    // "Anyone else" means anyone but the defender and the attacker: the
    // attacker has no reason to help block their own attack, so they are
    // not part of the Fellowship request.
    final everyoneElseDeclined = state.players
        .where((p) =>
            p.id != pending.defenderId &&
            p.id != pending.attackerId &&
            !p.isEliminated)
        .every((p) => declined.contains(p.id));

    final updatedPending = pending.copyWith(
      helpersDeclined: declined,
      // Once every other player has declined, the Fellowship request is
      // over and the defender falls back to their own defense window.
      fellowshipRequested: !everyoneElseDeclined,
    );
    return ActionSuccess(state.copyWith(pendingInterrupt: updatedPending));
  }

  return ActionSuccess(_checkEliminationWin(landPendingAttack(state)));
}

/// Last one standing: checked after anything that could eliminate a
/// player (a hit landing, in particular), independent of whose turn it is.
GameState _checkEliminationWin(GameState state) {
  if (state.isGameOver) return state;

  final activePlayers = state.players.where((p) => !p.isEliminated).toList();
  if (activePlayers.length != 1) return state;

  final winner = activePlayers.first;
  return state
      .copyWith(
        winner: WinResult(winnerId: winner.id, type: WinType.elimination),
      )
      .appendEvent(
        GameEnded(
          turnNumber: state.turnNumber,
          winnerId: winner.id,
          winType: WinType.elimination,
        ),
      );
}

/// Full restoration: only meaningful "at the start of your turn", so this
/// is checked once, right after turn rotation in [_endTurn], against the
/// newly-active player.
GameState _checkRestorationWin(GameState state) {
  if (state.isGameOver) return state;

  final active = state.activePlayer;
  if (!active.isFullyRestored) return state;

  return state
      .copyWith(
        winner: WinResult(winnerId: active.id, type: WinType.restoration),
      )
      .appendEvent(
        GameEnded(
          turnNumber: state.turnNumber,
          winnerId: active.id,
          winType: WinType.restoration,
        ),
      );
}
