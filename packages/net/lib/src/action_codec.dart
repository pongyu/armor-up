import 'package:game_engine/game_engine.dart';

/// Converts a [GameAction] to and from the JSON shape sent over the wire as
/// `{"type": "action", "action": <this>}`. Kept separate from the engine
/// package itself: game_engine has no network/JSON dependency by design, so
/// serialization lives at the transport boundary instead.
extension GameActionJson on GameAction {
  Map<String, dynamic> toJson() => switch (this) {
        DrawCard(:final playerId) => {
            'kind': 'DrawCard',
            'playerId': playerId,
          },
        PlayCard(
          :final playerId,
          :final cardInstanceId,
          :final targetPlayerId,
          :final targetArmor,
        ) =>
          {
            'kind': 'PlayCard',
            'playerId': playerId,
            'cardInstanceId': cardInstanceId,
            if (targetPlayerId != null) 'targetPlayerId': targetPlayerId,
            if (targetArmor != null) 'targetArmor': targetArmor.name,
          },
        DiscardCard(:final playerId, :final cardInstanceId) => {
            'kind': 'DiscardCard',
            'playerId': playerId,
            'cardInstanceId': cardInstanceId,
          },
        EndTurn(:final playerId) => {
            'kind': 'EndTurn',
            'playerId': playerId,
          },
        DeclareDefense(:final playerId, :final cardInstanceId) => {
            'kind': 'DeclareDefense',
            'playerId': playerId,
            'cardInstanceId': cardInstanceId,
          },
        DeclineDefense(:final playerId) => {
            'kind': 'DeclineDefense',
            'playerId': playerId,
          },
      };
}

/// Parses the JSON shape produced by [GameActionJson.toJson] back into a
/// [GameAction]. Throws [FormatException] on an unknown or malformed shape;
/// callers at the network boundary should catch this and reject the message
/// rather than let a malformed client payload crash the host.
GameAction gameActionFromJson(Map<String, dynamic> json) {
  final kind = json['kind'];
  final playerId = json['playerId'];
  if (kind is! String || playerId is! String) {
    throw FormatException('Malformed GameAction JSON: $json');
  }

  switch (kind) {
    case 'DrawCard':
      return DrawCard(playerId: playerId);
    case 'PlayCard':
      final cardInstanceId = json['cardInstanceId'];
      if (cardInstanceId is! String) {
        throw FormatException('PlayCard missing cardInstanceId: $json');
      }
      return PlayCard(
        playerId: playerId,
        cardInstanceId: cardInstanceId,
        targetPlayerId: json['targetPlayerId'] as String?,
        targetArmor: _armorTypeFromJson(json['targetArmor']),
      );
    case 'DiscardCard':
      final cardInstanceId = json['cardInstanceId'];
      if (cardInstanceId is! String) {
        throw FormatException('DiscardCard missing cardInstanceId: $json');
      }
      return DiscardCard(playerId: playerId, cardInstanceId: cardInstanceId);
    case 'EndTurn':
      return EndTurn(playerId: playerId);
    case 'DeclareDefense':
      final cardInstanceId = json['cardInstanceId'];
      if (cardInstanceId is! String) {
        throw FormatException('DeclareDefense missing cardInstanceId: $json');
      }
      return DeclareDefense(playerId: playerId, cardInstanceId: cardInstanceId);
    case 'DeclineDefense':
      return DeclineDefense(playerId: playerId);
    default:
      throw FormatException('Unknown GameAction kind: $kind');
  }
}

ArmorType? _armorTypeFromJson(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Malformed ArmorType JSON: $value');
  }
  return ArmorType.values.firstWhere(
    (t) => t.name == value,
    orElse: () => throw FormatException('Unknown ArmorType: $value'),
  );
}
