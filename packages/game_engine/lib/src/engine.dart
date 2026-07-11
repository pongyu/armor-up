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
export 'models/pending_group_discard.dart';
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

  if (state.pendingGroupDiscard != null) {
    return switch (action) {
      DiscardCard() => _discardCard(state, action),
      _ => const ActionFailure(
          'A group discard (e.g. Wilderness Season) is pending; only '
          'DiscardCard from a player who still owes one is valid right now',
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

/// Returns the index of the next player who still has armor, skipping over
/// any eliminated players. Eliminated players never get another turn - by
/// the time this is called the game is guaranteed to still have at least
/// two players with armor (otherwise elimination-win would already have
/// ended the game), so this always terminates.
int _nextActivePlayerIndex(GameState state) {
  var index = state.activePlayerIndex;
  do {
    index = (index + 1) % state.players.length;
  } while (state.players[index].isEliminated);
  return index;
}

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
    // Both piles are empty and there is nothing left to reshuffle: the
    // deck is exhausted, so the game ends immediately rather than
    // continuing indefinitely with players unable to draw.
    return ActionSuccess(_declareDeckExhaustedWinner(nextState));
  }

  return ActionSuccess(nextState.copyWith(hasDrawnThisTurn: true));
}

/// Ends the game when the deck is exhausted (draw pile and discard pile
/// both empty). The player closest to full restoration wins: most Strong
/// pieces first, then fewest Lost pieces, then earliest turn order as a
/// final tiebreak so the outcome is always deterministic.
GameState _declareDeckExhaustedWinner(GameState state) {
  final contenders = state.players.where((p) => !p.isEliminated).toList();
  contenders.sort((a, b) {
    final byStrong = b.strongPieceCount.compareTo(a.strongPieceCount);
    if (byStrong != 0) return byStrong;
    final byLost = a.lostPieceCount.compareTo(b.lostPieceCount);
    if (byLost != 0) return byLost;
    return state.indexOfPlayer(a.id).compareTo(state.indexOfPlayer(b.id));
  });

  final winner = contenders.first;
  return state
      .copyWith(
        winner: WinResult(winnerId: winner.id, type: WinType.deckExhausted),
      )
      .appendEvent(
        GameEnded(
          turnNumber: state.turnNumber,
          winnerId: winner.id,
          winType: WinType.deckExhausted,
        ),
      );
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
      switch (def.effect) {
        case EffectPrimitive.restoreOneStep:
          if (piece.condition != ArmorCondition.weakened) {
            return 'Target armor piece is not in the right condition for this card';
          }
        case EffectPrimitive.restoreFullyFromLost:
          if (piece.condition != ArmorCondition.lost) {
            return 'Target armor piece is not in the right condition for this card';
          }
        case EffectPrimitive.skipNextTurnAndRestore:
          // Fasting: "one piece (any state, including Lost) -> Strong
          // immediately". No condition restriction.
          break;
        default:
          throw StateError(
            '${def.id} uses TargetRule.ownArmorPiece with an unhandled '
            'effect ${def.effect}',
          );
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

  final pendingGroup = state.pendingGroupDiscard;
  if (pendingGroup != null) {
    if (!pendingGroup.owedPlayerIds.contains(action.playerId)) {
      return const ActionFailure(
        'A group discard is pending and this player does not owe one',
      );
    }
    // An owed group discard (e.g. from Wilderness Season) is allowed
    // regardless of turn order or draw/play state, and never counts as
    // this turn's one action.
    var working = _removeCardAndLog(state, action, cardInstance);
    final remaining = {...pendingGroup.owedPlayerIds}..remove(action.playerId);
    working = working.copyWith(
      pendingGroupDiscard: remaining.isEmpty ? null : pendingGroup.copyWith(owedPlayerIds: remaining),
      clearPendingGroupDiscard: remaining.isEmpty,
    );
    return ActionSuccess(working);
  }

  // Normal turn-flow discard: only the active player, and only after
  // drawing.
  if (!_isActivePlayer(state, action.playerId)) {
    return const ActionFailure('Only the active player may discard right now');
  }
  if (!state.hasDrawnThisTurn) {
    return const ActionFailure('Must draw before discarding');
  }

  // A hand at or under the limit means this discard IS the player's one
  // turn action (mutually exclusive with PlayCard, per "play exactly 1
  // card, OR discard 1 card"); above the limit, it's mandatory hand-limit
  // cleanup and is always allowed once drawn, regardless of whether a
  // card was already played this turn.
  final isHandLimitCleanup = player.hand.length > maxHandSize;
  if (!isHandLimitCleanup && state.hasPlayedCardThisTurn) {
    return const ActionFailure(
      'Already played a card this turn; further discards are only '
      'allowed to get under the hand limit',
    );
  }

  var working = _removeCardAndLog(state, action, cardInstance);
  if (!isHandLimitCleanup) {
    working = working.copyWith(hasPlayedCardThisTurn: true);
  }
  return ActionSuccess(working);
}

/// Shared tail of [_discardCard]: moves [cardInstance] from
/// [action.playerId]'s hand to the discard pile and logs [CardDiscarded].
GameState _removeCardAndLog(
  GameState state,
  DiscardCard action,
  CardInstance cardInstance,
) {
  var working = state.updatePlayer(
    action.playerId,
    (p) => p.copyWith(
      hand: p.hand.where((c) => c.instanceId != cardInstance.instanceId).toList(),
    ),
  );
  working = working.copyWith(discardPile: [...working.discardPile, cardInstance]);
  return working.appendEvent(
    CardDiscarded(
      turnNumber: working.turnNumber,
      playerId: action.playerId,
      cardDefId: cardInstance.defId,
    ),
  );
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

  final nextIndex = _nextActivePlayerIndex(working);
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

  // A system decline (net-layer response-deadline expiry) resolves via
  // the exact same logic below as a player choosing to decline - only an
  // extra DefenseTimedOut log entry distinguishes it, so UI built on the
  // event log can show "ran out of time" instead of implying a choice.
  var working = state;
  if (action.isSystemDecline) {
    working = working.appendEvent(
      DefenseTimedOut(
        turnNumber: working.turnNumber,
        playerId: action.playerId,
        wasHelper: isHelper,
      ),
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
    return ActionSuccess(working.copyWith(pendingInterrupt: updatedPending));
  }

  return ActionSuccess(_checkEliminationWin(landPendingAttack(working)));
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
