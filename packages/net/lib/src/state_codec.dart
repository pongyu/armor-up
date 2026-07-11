import 'package:game_engine/game_engine.dart';

/// JSON codec for the full, unfiltered [GameState]. Only ever used
/// host-side (to persist/replay/debug); never sent to a client directly —
/// clients always receive the output of [filterStateForPlayer] instead. See
/// `filtered_state.dart`.
extension GameStateJson on GameState {
  Map<String, dynamic> toJson() => {
        'players': players.map((p) => p.toJson()).toList(),
        'activePlayerIndex': activePlayerIndex,
        'drawPile': drawPile.map((c) => c.toJson()).toList(),
        'discardPile': discardPile.map((c) => c.toJson()).toList(),
        'rngSeed': rngSeed,
        'rngDrawCount': rngDrawCount,
        'nextInstanceId': nextInstanceId,
        'turnNumber': turnNumber,
        'eventLog': eventLog.map((e) => e.toJson()).toList(),
        if (winner != null) 'winner': winner!.toJson(),
        if (pendingInterrupt != null)
          'pendingInterrupt': pendingInterrupt!.toJson(),
        if (pendingGroupDiscard != null)
          'pendingGroupDiscard': pendingGroupDiscard!.toJson(),
        'hasDrawnThisTurn': hasDrawnThisTurn,
        'hasPlayedCardThisTurn': hasPlayedCardThisTurn,
      };

  static GameState fromJson(Map<String, dynamic> json) => GameState(
        players: (json['players'] as List)
            .map((p) => PlayerStateJson.fromJson(p as Map<String, dynamic>))
            .toList(),
        activePlayerIndex: json['activePlayerIndex'] as int,
        drawPile: (json['drawPile'] as List)
            .map((c) => CardInstanceJson.fromJson(c as Map<String, dynamic>))
            .toList(),
        discardPile: (json['discardPile'] as List)
            .map((c) => CardInstanceJson.fromJson(c as Map<String, dynamic>))
            .toList(),
        rngSeed: json['rngSeed'] as int,
        rngDrawCount: json['rngDrawCount'] as int,
        nextInstanceId: json['nextInstanceId'] as int,
        turnNumber: json['turnNumber'] as int,
        eventLog: (json['eventLog'] as List)
            .map((e) => gameEventFromJson(e as Map<String, dynamic>))
            .toList(),
        winner: json['winner'] == null
            ? null
            : WinResultJson.fromJson(json['winner'] as Map<String, dynamic>),
        pendingInterrupt: json['pendingInterrupt'] == null
            ? null
            : PendingAttackJson.fromJson(
                json['pendingInterrupt'] as Map<String, dynamic>),
        pendingGroupDiscard: json['pendingGroupDiscard'] == null
            ? null
            : PendingGroupDiscardJson.fromJson(
                json['pendingGroupDiscard'] as Map<String, dynamic>),
        hasDrawnThisTurn: json['hasDrawnThisTurn'] as bool,
        hasPlayedCardThisTurn: json['hasPlayedCardThisTurn'] as bool,
      );
}

extension PlayerStateJson on PlayerState {
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'armor': armor.map((a) => a.toJson()).toList(),
        'hand': hand.map((c) => c.toJson()).toList(),
        'isFasting': isFasting,
        'fastingScheduled': fastingScheduled,
        'wasEverDamaged': wasEverDamaged,
      };

  static PlayerState fromJson(Map<String, dynamic> json) => PlayerState(
        id: json['id'] as String,
        name: json['name'] as String,
        armor: (json['armor'] as List)
            .map((a) => ArmorPieceJson.fromJson(a as Map<String, dynamic>))
            .toList(),
        hand: (json['hand'] as List)
            .map((c) => CardInstanceJson.fromJson(c as Map<String, dynamic>))
            .toList(),
        isFasting: json['isFasting'] as bool,
        fastingScheduled: json['fastingScheduled'] as bool,
        wasEverDamaged: json['wasEverDamaged'] as bool,
      );
}

extension CardInstanceJson on CardInstance {
  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'defId': defId,
      };

  static CardInstance fromJson(Map<String, dynamic> json) => CardInstance(
        instanceId: json['instanceId'] as String,
        defId: json['defId'] as String,
      );
}

extension ArmorPieceJson on ArmorPiece {
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'condition': condition.name,
      };

  static ArmorPiece fromJson(Map<String, dynamic> json) => ArmorPiece(
        type: ArmorType.values.byName(json['type'] as String),
        condition: ArmorCondition.values.byName(json['condition'] as String),
      );
}

extension WinResultJson on WinResult {
  Map<String, dynamic> toJson() => {
        'winnerId': winnerId,
        'type': type.name,
      };

  static WinResult fromJson(Map<String, dynamic> json) => WinResult(
        winnerId: json['winnerId'] as String,
        type: WinType.values.byName(json['type'] as String),
      );
}

extension PendingAttackJson on PendingAttack {
  Map<String, dynamic> toJson() => {
        'attackCardDefId': attackCardDefId,
        'attackCardInstanceId': attackCardInstanceId,
        'attackerId': attackerId,
        'defenderId': defenderId,
        'targetArmor': targetArmor.name,
        'isDoubleHit': isDoubleHit,
        'fellowshipRequested': fellowshipRequested,
        'helpersDeclined': helpersDeclined.toList(),
      };

  static PendingAttack fromJson(Map<String, dynamic> json) => PendingAttack(
        attackCardDefId: json['attackCardDefId'] as String,
        attackCardInstanceId: json['attackCardInstanceId'] as String,
        attackerId: json['attackerId'] as String,
        defenderId: json['defenderId'] as String,
        targetArmor: ArmorType.values.byName(json['targetArmor'] as String),
        isDoubleHit: json['isDoubleHit'] as bool,
        fellowshipRequested: json['fellowshipRequested'] as bool,
        helpersDeclined:
            (json['helpersDeclined'] as List).map((e) => e as String).toSet(),
      );
}

extension PendingGroupDiscardJson on PendingGroupDiscard {
  Map<String, dynamic> toJson() => {
        'owedPlayerIds': owedPlayerIds.toList(),
      };

  static PendingGroupDiscard fromJson(Map<String, dynamic> json) =>
      PendingGroupDiscard(
        owedPlayerIds:
            (json['owedPlayerIds'] as List).map((e) => e as String).toSet(),
      );
}

extension GameEventJson on GameEvent {
  Map<String, dynamic> toJson() => switch (this) {
        CardPlayed(
          :final turnNumber,
          :final playerId,
          :final cardDefId,
          :final targetPlayerId,
          :final targetArmor,
        ) =>
          {
            'kind': 'CardPlayed',
            'turnNumber': turnNumber,
            'playerId': playerId,
            'cardDefId': cardDefId,
            if (targetPlayerId != null) 'targetPlayerId': targetPlayerId,
            if (targetArmor != null) 'targetArmor': targetArmor.name,
          },
        ArmorWeakened(:final turnNumber, :final playerId, :final armor) => {
            'kind': 'ArmorWeakened',
            'turnNumber': turnNumber,
            'playerId': playerId,
            'armor': armor.name,
          },
        ArmorLost(:final turnNumber, :final playerId, :final armor) => {
            'kind': 'ArmorLost',
            'turnNumber': turnNumber,
            'playerId': playerId,
            'armor': armor.name,
          },
        ArmorRestored(
          :final turnNumber,
          :final playerId,
          :final armor,
          :final newCondition,
        ) =>
          {
            'kind': 'ArmorRestored',
            'turnNumber': turnNumber,
            'playerId': playerId,
            'armor': armor.name,
            'newCondition': newCondition.name,
          },
        AttackBlocked(
          :final turnNumber,
          :final defenderId,
          :final byCardDefId,
          :final helperId,
        ) =>
          {
            'kind': 'AttackBlocked',
            'turnNumber': turnNumber,
            'defenderId': defenderId,
            'byCardDefId': byCardDefId,
            if (helperId != null) 'helperId': helperId,
          },
        AttackReflected(
          :final turnNumber,
          :final originalAttackerId,
          :final newDefenderId,
          :final attackCardDefId,
        ) =>
          {
            'kind': 'AttackReflected',
            'turnNumber': turnNumber,
            'originalAttackerId': originalAttackerId,
            'newDefenderId': newDefenderId,
            'attackCardDefId': attackCardDefId,
          },
        TurnSkipped(:final turnNumber, :final playerId, :final reason) => {
            'kind': 'TurnSkipped',
            'turnNumber': turnNumber,
            'playerId': playerId,
            'reason': reason,
          },
        CardDrawn(:final turnNumber, :final playerId) => {
            'kind': 'CardDrawn',
            'turnNumber': turnNumber,
            'playerId': playerId,
          },
        CardDiscarded(:final turnNumber, :final playerId, :final cardDefId) => {
            'kind': 'CardDiscarded',
            'turnNumber': turnNumber,
            'playerId': playerId,
            'cardDefId': cardDefId,
          },
        CardStolen(
          :final turnNumber,
          :final thiefId,
          :final victimId,
          :final cardDefId,
        ) =>
          {
            'kind': 'CardStolen',
            'turnNumber': turnNumber,
            'thiefId': thiefId,
            'victimId': victimId,
            'cardDefId': cardDefId,
          },
        DeckReshuffled(:final turnNumber) => {
            'kind': 'DeckReshuffled',
            'turnNumber': turnNumber,
          },
        GameEnded(:final turnNumber, :final winnerId, :final winType) => {
            'kind': 'GameEnded',
            'turnNumber': turnNumber,
            'winnerId': winnerId,
            'winType': winType.name,
          },
      };
}

GameEvent gameEventFromJson(Map<String, dynamic> json) {
  final kind = json['kind'] as String;
  final turnNumber = json['turnNumber'] as int;
  switch (kind) {
    case 'CardPlayed':
      return CardPlayed(
        turnNumber: turnNumber,
        playerId: json['playerId'] as String,
        cardDefId: json['cardDefId'] as String,
        targetPlayerId: json['targetPlayerId'] as String?,
        targetArmor: json['targetArmor'] == null
            ? null
            : ArmorType.values.byName(json['targetArmor'] as String),
      );
    case 'ArmorWeakened':
      return ArmorWeakened(
        turnNumber: turnNumber,
        playerId: json['playerId'] as String,
        armor: ArmorType.values.byName(json['armor'] as String),
      );
    case 'ArmorLost':
      return ArmorLost(
        turnNumber: turnNumber,
        playerId: json['playerId'] as String,
        armor: ArmorType.values.byName(json['armor'] as String),
      );
    case 'ArmorRestored':
      return ArmorRestored(
        turnNumber: turnNumber,
        playerId: json['playerId'] as String,
        armor: ArmorType.values.byName(json['armor'] as String),
        newCondition:
            ArmorCondition.values.byName(json['newCondition'] as String),
      );
    case 'AttackBlocked':
      return AttackBlocked(
        turnNumber: turnNumber,
        defenderId: json['defenderId'] as String,
        byCardDefId: json['byCardDefId'] as String,
        helperId: json['helperId'] as String?,
      );
    case 'AttackReflected':
      return AttackReflected(
        turnNumber: turnNumber,
        originalAttackerId: json['originalAttackerId'] as String,
        newDefenderId: json['newDefenderId'] as String,
        attackCardDefId: json['attackCardDefId'] as String,
      );
    case 'TurnSkipped':
      return TurnSkipped(
        turnNumber: turnNumber,
        playerId: json['playerId'] as String,
        reason: json['reason'] as String,
      );
    case 'CardDrawn':
      return CardDrawn(turnNumber: turnNumber, playerId: json['playerId'] as String);
    case 'CardDiscarded':
      return CardDiscarded(
        turnNumber: turnNumber,
        playerId: json['playerId'] as String,
        cardDefId: json['cardDefId'] as String,
      );
    case 'CardStolen':
      return CardStolen(
        turnNumber: turnNumber,
        thiefId: json['thiefId'] as String,
        victimId: json['victimId'] as String,
        cardDefId: json['cardDefId'] as String,
      );
    case 'DeckReshuffled':
      return DeckReshuffled(turnNumber: turnNumber);
    case 'GameEnded':
      return GameEnded(
        turnNumber: turnNumber,
        winnerId: json['winnerId'] as String,
        winType: WinType.values.byName(json['winType'] as String),
      );
    default:
      throw FormatException('Unknown GameEvent kind: $kind');
  }
}
