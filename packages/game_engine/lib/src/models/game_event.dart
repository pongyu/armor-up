import 'armor.dart';
import 'win_result.dart';

/// Base type for every typed entry appended to [GameState.eventLog] as
/// actions are applied. The hotseat UI renders these as a scrolling text
/// log; later they drive animations and network sync debugging.
sealed class GameEvent {
  final int turnNumber;

  const GameEvent({required this.turnNumber});

  /// Ids of the players allowed to see this event's full details (e.g. the
  /// thief in a [CardStolen]). Null (the default, and the only value every
  /// event type used before this field existed) means public: visible to
  /// everyone exactly as logged, no redaction. A non-null list is always
  /// used together with [redacted] - see that method's doc comment. A
  /// getter (derived from the event's own fields) rather than a
  /// constructor parameter, so every event type - restricted or not - can
  /// stay a plain `const` constructor.
  List<String>? get visibleTo => null;

  /// The public-safe form of this event, shown in place of the real one
  /// to any viewer not listed in [visibleTo]. For a public event
  /// ([visibleTo] null) this is always `this` unchanged. A restricted
  /// event must override this to strip the sensitive detail (see
  /// [CardStolen.redacted]) rather than ever being sent/rendered as-is to
  /// an unlisted viewer.
  GameEvent redacted() => this;
}

final class CardPlayed extends GameEvent {
  final String playerId;
  final String cardDefId;
  final String? targetPlayerId;
  final ArmorType? targetArmor;

  const CardPlayed({
    required super.turnNumber,
    required this.playerId,
    required this.cardDefId,
    this.targetPlayerId,
    this.targetArmor,
  });

  @override
  String toString() => 'CardPlayed($playerId played $cardDefId'
      '${targetPlayerId != null ? ' -> $targetPlayerId' : ''}'
      '${targetArmor != null ? ' (${targetArmor!.name})' : ''})';
}

final class ArmorWeakened extends GameEvent {
  final String playerId;
  final ArmorType armor;

  const ArmorWeakened({
    required super.turnNumber,
    required this.playerId,
    required this.armor,
  });

  @override
  String toString() => 'ArmorWeakened($playerId, ${armor.name})';
}

final class ArmorLost extends GameEvent {
  final String playerId;
  final ArmorType armor;

  const ArmorLost({
    required super.turnNumber,
    required this.playerId,
    required this.armor,
  });

  @override
  String toString() => 'ArmorLost($playerId, ${armor.name})';
}

final class ArmorRestored extends GameEvent {
  final String playerId;
  final ArmorType armor;
  final ArmorCondition newCondition;

  const ArmorRestored({
    required super.turnNumber,
    required this.playerId,
    required this.armor,
    required this.newCondition,
  });

  @override
  String toString() =>
      'ArmorRestored($playerId, ${armor.name} -> ${newCondition.name})';
}

final class AttackBlocked extends GameEvent {
  final String defenderId;
  final String byCardDefId;
  final String? helperId;

  const AttackBlocked({
    required super.turnNumber,
    required this.defenderId,
    required this.byCardDefId,
    this.helperId,
  });

  @override
  String toString() => 'AttackBlocked($defenderId by $byCardDefId'
      '${helperId != null ? ' via $helperId' : ''})';
}

final class AttackReflected extends GameEvent {
  final String originalAttackerId;
  final String newDefenderId;
  final String attackCardDefId;

  const AttackReflected({
    required super.turnNumber,
    required this.originalAttackerId,
    required this.newDefenderId,
    required this.attackCardDefId,
  });

  @override
  String toString() =>
      'AttackReflected($attackCardDefId back at $originalAttackerId)';
}

final class TurnSkipped extends GameEvent {
  final String playerId;
  final String reason;

  const TurnSkipped({
    required super.turnNumber,
    required this.playerId,
    required this.reason,
  });

  @override
  String toString() => 'TurnSkipped($playerId, $reason)';
}

final class CardDrawn extends GameEvent {
  final String playerId;

  const CardDrawn({required super.turnNumber, required this.playerId});

  @override
  String toString() => 'CardDrawn($playerId)';
}

final class CardDiscarded extends GameEvent {
  final String playerId;
  final String cardDefId;

  const CardDiscarded({
    required super.turnNumber,
    required this.playerId,
    required this.cardDefId,
  });

  @override
  String toString() => 'CardDiscarded($playerId, $cardDefId)';
}

/// Logged when Road to Damascus steals a card. Per the game's ruling, the
/// table sees THAT a card was stolen, not WHICH card - only the thief (who
/// has it in hand) is allowed to see [cardDefId]; the victim may deduce it
/// from their own remaining hand, but nothing here helps them do so
/// automatically. [visibleTo] is `[thiefId]`, so every other viewer
/// (including the victim and any bystander) sees [redacted] instead.
final class CardStolen extends GameEvent {
  final String thiefId;
  final String victimId;
  final String cardDefId;

  const CardStolen({
    required super.turnNumber,
    required this.thiefId,
    required this.victimId,
    required this.cardDefId,
  });

  @override
  List<String> get visibleTo => [thiefId];

  @override
  CardStolenRedacted redacted() => CardStolenRedacted(
        turnNumber: turnNumber,
        thiefId: thiefId,
        victimId: victimId,
      );

  @override
  String toString() => 'CardStolen($thiefId stole $cardDefId from $victimId)';
}

/// The public-safe form of a [CardStolen] event: everything except
/// [CardStolen.cardDefId], which viewers outside [CardStolen.visibleTo]
/// are never allowed to see. A distinct event type (rather than
/// [CardStolen] with a nullable/omitted [CardStolen.cardDefId]) so the
/// event union stays exhaustively switchable and callers can't
/// accidentally treat a redacted instance as carrying real card data.
final class CardStolenRedacted extends GameEvent {
  final String thiefId;
  final String victimId;

  const CardStolenRedacted({
    required super.turnNumber,
    required this.thiefId,
    required this.victimId,
  });

  @override
  String toString() => 'CardStolenRedacted($thiefId stole a card from $victimId)';
}

/// Logged instead of a normal decline whenever a [DeclineDefense] with
/// `isSystemDecline: true` resolves - i.e. the net layer's
/// defense-response deadline expired for [playerId] rather than them
/// declining by choice. [wasHelper] distinguishes a Fellowship helper's
/// turn to respond timing out (the request falls through to the next
/// helper, or back to the defender) from the defender's own window
/// timing out (the attack lands).
final class DefenseTimedOut extends GameEvent {
  final String playerId;
  final bool wasHelper;

  const DefenseTimedOut({
    required super.turnNumber,
    required this.playerId,
    required this.wasHelper,
  });

  @override
  String toString() => 'DefenseTimedOut($playerId'
      '${wasHelper ? ', helper' : ''})';
}

/// Logged the moment a player's last armor piece drops to Lost. Their
/// hand (size [cardsDiscarded]) is moved to the discard pile in the same
/// state transition, since an eliminated player never gets another turn
/// to play or discard it themselves.
final class PlayerEliminated extends GameEvent {
  final String playerId;
  final int cardsDiscarded;

  const PlayerEliminated({
    required super.turnNumber,
    required this.playerId,
    required this.cardsDiscarded,
  });

  @override
  String toString() =>
      'PlayerEliminated($playerId, $cardsDiscarded cards discarded)';
}

final class DeckReshuffled extends GameEvent {
  const DeckReshuffled({required super.turnNumber});

  @override
  String toString() => 'DeckReshuffled()';
}

final class GameEnded extends GameEvent {
  final String winnerId;
  final WinType winType;

  const GameEnded({
    required super.turnNumber,
    required this.winnerId,
    required this.winType,
  });

  @override
  String toString() => 'GameEnded($winnerId, ${winType.name})';
}
