import 'armor.dart';
import 'win_result.dart';

/// Base type for every typed entry appended to [GameState.eventLog] as
/// actions are applied. The hotseat UI renders these as a scrolling text
/// log; later they drive animations and network sync debugging.
sealed class GameEvent {
  final int turnNumber;

  const GameEvent({required this.turnNumber});
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
  String toString() => 'CardStolen($thiefId stole $cardDefId from $victimId)';
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
