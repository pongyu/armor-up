import 'actions/game_action.dart';
import 'deck.dart';
import 'models/armor.dart';
import 'models/card.dart';
import 'models/game_event.dart';
import 'models/game_state.dart';
import 'models/pending_group_discard.dart';
import 'models/pending_interrupt.dart';
import 'rng.dart';

/// Resolves the effect of a just-played non-defense card. [state] already
/// has the card removed from the player's hand and appended to the
/// discard pile, and a [CardPlayed] event logged. This function applies
/// the card's game-rule consequences (attack, restore, or event) and
/// returns the resulting state.
GameState resolveEffect({
  required GameState state,
  required CardDef def,
  required PlayCard action,
}) {
  switch (def.effect) {
    case EffectPrimitive.weakenOrHit:
    case EffectPrimitive.doubleHit:
      return _beginAttack(state: state, def: def, action: action);

    case EffectPrimitive.restoreOneStep:
      return _applyArmorCondition(
        state: state,
        playerId: action.playerId,
        armorType: action.targetArmor!,
        newCondition: ArmorCondition.strong,
      );

    case EffectPrimitive.restoreFullyFromLost:
      return _applyArmorCondition(
        state: state,
        playerId: action.playerId,
        armorType: action.targetArmor!,
        newCondition: ArmorCondition.strong,
      );

    case EffectPrimitive.skipNextTurnAndRestore:
      // Neither the skipped turn nor the restoration happens yet: playing
      // Fasting only commits to both. The TurnSkipped event is logged
      // when the skip actually takes effect, and the restore (plus its
      // ArmorRestored event) fires at the END of the fasted turn - both
      // in _endTurn's turn-rotation logic in engine.dart. This mirrors
      // the real card: choosing what to fast for is instant, but nothing
      // heals until the fast is actually endured.
      return state.updatePlayer(
        action.playerId,
        (p) => p.copyWith(
          fastingScheduled: true,
          fastingRestoreTarget: action.targetArmor!,
        ),
      );

    case EffectPrimitive.allWeakenedToLost:
      return _jerichoMarch(state);

    case EffectPrimitive.allDiscardOne:
      // Every player with at least one card owes a discard, tracked as an
      // engine-level obligation (see PendingGroupDiscard) so applyAction
      // can gate to exactly the right DiscardCard actions until everyone
      // has gone. A player with an empty hand (including the one who just
      // played this card, if it was their last) has nothing to discard
      // and is excluded, so the obligation can always be fully resolved.
      final owed = {
        for (final p in state.players)
          if (p.hand.isNotEmpty) p.id,
      };
      if (owed.isEmpty) return state;
      return state.copyWith(
        pendingGroupDiscard: PendingGroupDiscard(owedPlayerIds: owed),
      );

    case EffectPrimitive.stealRandomCard:
      return _roadToDamascus(state: state, action: action);

    case EffectPrimitive.blockAttack:
    case EffectPrimitive.reflectAttack:
    case EffectPrimitive.fellowshipRequest:
      throw StateError(
        'Defense effects must be resolved via resolveDefense, not resolveEffect',
      );
  }
}

GameState _applyArmorCondition({
  required GameState state,
  required String playerId,
  required ArmorType armorType,
  required ArmorCondition newCondition,
}) {
  final working =
      state.updatePlayer(playerId, (p) => p.withArmorCondition(armorType, newCondition));
  final announced = working.appendEvent(
    ArmorRestored(
      turnNumber: working.turnNumber,
      playerId: playerId,
      armor: armorType,
      newCondition: newCondition,
    ),
  );
  return announceIfNewlyFullyRestored(before: state, after: announced, playerId: playerId);
}

/// Logs [RestorationImminent] for [playerId] if their [PlayerState.isFullyRestored]
/// just transitioned from false (in [before]) to true (in [after]) -
/// never repeatedly while it continues to hold, and never when
/// [GameState.restorationWinEnabled] is false. Shared by every place
/// armor can be restored (Renewal/Armor Bearer via [_applyArmorCondition]
/// here, and Fasting's delayed completion in engine.dart's `_endTurn`,
/// which cannot call a private function in this library and so calls
/// this exported helper directly).
GameState announceIfNewlyFullyRestored({
  required GameState before,
  required GameState after,
  required String playerId,
}) {
  if (!after.restorationWinEnabled) return after;
  final wasFullyRestored = before.playerById(playerId).isFullyRestored;
  final isFullyRestored = after.playerById(playerId).isFullyRestored;
  if (wasFullyRestored || !isFullyRestored) return after;
  return after.appendEvent(
    RestorationImminent(turnNumber: after.turnNumber, playerId: playerId),
  );
}

// ---------------------------------------------------------------------------
// Attacks
// ---------------------------------------------------------------------------

/// Starts attack resolution. If the defender holds any defense card, this
/// opens a [PendingAttack] interrupt instead of landing immediately;
/// otherwise the hit applies right away.
GameState _beginAttack({
  required GameState state,
  required CardDef def,
  required PlayCard action,
}) {
  final targetArmor = def.fixedTarget ?? action.targetArmor!;
  final pending = PendingAttack(
    attackCardDefId: def.id,
    attackCardInstanceId: action.cardInstanceId,
    attackerId: action.playerId,
    defenderId: action.targetPlayerId!,
    targetArmor: targetArmor,
    isDoubleHit: def.effect == EffectPrimitive.doubleHit,
  );

  final defender = state.playerById(pending.defenderId);

  // A shield earned by helping via Fellowship (see resolveDefense's
  // blockAttack case) auto-blocks the very next attack against its
  // owner for free, then is consumed - no card spent, no interrupt
  // opened, regardless of whether the defender holds a defense card.
  if (defender.isShielded) {
    final working = state.updatePlayer(
      pending.defenderId,
      (p) => p.copyWith(isShielded: false),
    );
    return working.appendEvent(
      AttackBlockedByShield(
        turnNumber: working.turnNumber,
        defenderId: pending.defenderId,
        attackCardDefId: def.id,
      ),
    );
  }

  final defenderHasDefenseCard = defender.hand
      .any((c) => cardDefById(c.defId).type == CardType.defense);

  if (!defenderHasDefenseCard) {
    return landPendingAttack(state.copyWith(pendingInterrupt: pending));
  }

  return state.copyWith(pendingInterrupt: pending);
}

/// Applies the hit from [GameState.pendingInterrupt] to its target armor
/// piece and clears the interrupt. Called when an attack goes undefended
/// (no defense card held, or the defender/table declines).
GameState landPendingAttack(GameState state) {
  final pending = state.pendingInterrupt!;
  var working = state.copyWith(clearPendingInterrupt: true);

  final defender = working.playerById(pending.defenderId);
  final before = defender.armorOf(pending.targetArmor).condition;
  if (before == ArmorCondition.lost) {
    // Already lost (e.g. a second attack resolved against it while this
    // one was pending elsewhere) - no further effect, but still log the
    // attack having landed with no consequence via no event.
    return working;
  }

  final after = pending.isDoubleHit
      ? ArmorCondition.lost
      : before.stepDown();

  working = working.updatePlayer(
    pending.defenderId,
    (p) => p.withArmorCondition(pending.targetArmor, after),
  );

  working = working.appendEvent(
    after == ArmorCondition.lost
        ? ArmorLost(
            turnNumber: working.turnNumber,
            playerId: pending.defenderId,
            armor: pending.targetArmor,
          )
        : ArmorWeakened(
            turnNumber: working.turnNumber,
            playerId: pending.defenderId,
            armor: pending.targetArmor,
          ),
  );

  return _discardHandsOfNewlyEliminated(before: state, after: working);
}

/// Compares [before] and [after] for players who just crossed from not
/// eliminated to eliminated, moves each such player's hand to the discard
/// pile, and logs a [PlayerEliminated] event per player. An eliminated
/// player never gets another turn to play or discard their hand
/// themselves, so it would otherwise sit as unreachable dead state for
/// the rest of the game.
///
/// Compares against [before] (not just "hand non-empty") so a player who
/// was already eliminated earlier in the game - and thus already had
/// their hand cleared - is never re-processed, even though their hand is
/// empty either way.
GameState _discardHandsOfNewlyEliminated({
  required GameState before,
  required GameState after,
}) {
  var working = after;
  for (final player in after.players) {
    final wasEliminated = before.playerById(player.id).isEliminated;
    if (wasEliminated || !player.isEliminated || player.hand.isEmpty) {
      continue;
    }
    final discarded = player.hand;
    working = working.updatePlayer(player.id, (p) => p.copyWith(hand: const []));
    working = working.copyWith(
      discardPile: [...working.discardPile, ...discarded],
    );
    working = working.appendEvent(
      PlayerEliminated(
        turnNumber: working.turnNumber,
        playerId: player.id,
        cardsDiscarded: discarded.length,
      ),
    );
  }
  return working;
}

// ---------------------------------------------------------------------------
// Defense responses
// ---------------------------------------------------------------------------

/// Resolves a [DeclareDefense] action: [def] is the defense card the
/// responder ([responderId]) chose to play, already moved to the discard
/// pile by the caller. [isHelper] is true when this response comes from a
/// Fellowship helper rather than the defender themself.
GameState resolveDefense({
  required GameState state,
  required CardDef def,
  required String responderId,
  required bool isHelper,
}) {
  final pending = state.pendingInterrupt!;

  switch (def.effect) {
    case EffectPrimitive.blockAttack:
      var working = state.copyWith(clearPendingInterrupt: true);
      working = working.appendEvent(
        AttackBlocked(
          turnNumber: working.turnNumber,
          defenderId: pending.defenderId,
          byCardDefId: def.id,
          helperId: isHelper ? responderId : null,
        ),
      );
      // Reciprocity for a Fellowship helper: fellowship in Ecc 4:9-12 is
      // mutual, not one-directional charity, so the helper is rewarded
      // directly rather than just spending a card for someone else's
      // benefit - their own next incoming attack is auto-blocked for free.
      if (isHelper) {
        working = working.updatePlayer(
          responderId,
          (p) => p.copyWith(isShielded: true),
        );
        working = working.appendEvent(
          PlayerShielded(turnNumber: working.turnNumber, playerId: responderId),
        );
      }
      return working;

    case EffectPrimitive.reflectAttack:
      final reflected = pending.reflected();
      var working = state.copyWith(pendingInterrupt: reflected);
      working = working.appendEvent(
        AttackReflected(
          turnNumber: working.turnNumber,
          originalAttackerId: pending.attackerId,
          newDefenderId: reflected.defenderId,
          attackCardDefId: pending.attackCardDefId,
        ),
      );

      // The new defender (the original attacker) may now respond in turn;
      // if they hold no defense card, the reflected hit lands immediately.
      final newDefender = working.playerById(reflected.defenderId);
      final newDefenderHasDefenseCard = newDefender.hand
          .any((c) => cardDefById(c.defId).type == CardType.defense);
      if (!newDefenderHasDefenseCard) {
        return landPendingAttack(working);
      }
      return working;

    case EffectPrimitive.fellowshipRequest:
      return state.copyWith(
        pendingInterrupt: pending.copyWith(
          fellowshipRequested: true,
          helpersDeclined: const {},
        ),
      );

    default:
      throw StateError('${def.id} is not a defense card');
  }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

GameState _jerichoMarch(GameState state) {
  var working = state;
  for (final player in working.players) {
    for (final piece in player.armor) {
      if (piece.condition == ArmorCondition.weakened) {
        working = working.updatePlayer(
          player.id,
          (p) => p.withArmorCondition(piece.type, ArmorCondition.lost),
        );
        working = working.appendEvent(
          ArmorLost(
            turnNumber: working.turnNumber,
            playerId: player.id,
            armor: piece.type,
          ),
        );
      }
    }
  }
  // A single Jericho March can push more than one player's last piece to
  // Lost in the same resolution (unlike a single-target attack), so this
  // must check every player against their pre-march elimination status,
  // not just the last one touched.
  return _discardHandsOfNewlyEliminated(before: state, after: working);
}

GameState _roadToDamascus({
  required GameState state,
  required PlayCard action,
}) {
  final victim = state.playerById(action.targetPlayerId!);
  // _validateTarget rejects an empty-handed target before this point; an
  // empty hand here would mean that check was bypassed, which is a
  // programmer error, not a game-rule violation.
  assert(victim.hand.isNotEmpty, 'Road to Damascus target has no cards');
  final random = GameRandom(seed: state.rngSeed, drawCount: state.rngDrawCount);
  final index = random.nextInt(victim.hand.length);
  final stolen = victim.hand[index];

  var working = state.copyWith(rngDrawCount: random.drawCount);
  working = working.updatePlayer(
    victim.id,
    (p) => p.copyWith(
      hand: [...p.hand]..removeAt(index),
    ),
  );
  working = working.updatePlayer(
    action.playerId,
    (p) => p.copyWith(hand: [...p.hand, stolen]),
  );
  working = working.appendEvent(
    CardStolen(
      turnNumber: working.turnNumber,
      thiefId: action.playerId,
      victimId: victim.id,
      cardDefId: stolen.defId,
    ),
  );
  return working;
}
