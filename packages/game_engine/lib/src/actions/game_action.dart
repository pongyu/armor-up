import '../models/armor.dart';

/// Base type for every player input. All game input flows through
/// [GameAction] instances into the single `applyAction` entry point, so a
/// future network layer can inject actions from remote players without
/// touching engine internals.
sealed class GameAction {
  /// The player issuing this action. For most actions this must be the
  /// active player; [DeclareDefense], [DeclineDefense], and
  /// [FellowshipHelp] are the exceptions, validated against the current
  /// [PendingInterrupt] instead.
  final String playerId;

  const GameAction({required this.playerId});
}

/// Draw a card at the start of the acting player's turn.
final class DrawCard extends GameAction {
  const DrawCard({required super.playerId});

  @override
  String toString() => 'DrawCard($playerId)';
}

/// Play a card from hand. [targetPlayerId] is required for cards whose
/// [TargetRule] is `specificArmorOnPlayer`, `anyPieceOnPlayer`, or
/// `singlePlayer`. [targetArmor] is required for `anyPieceOnPlayer` and
/// `ownArmorPiece` cards.
final class PlayCard extends GameAction {
  final String cardInstanceId;
  final String? targetPlayerId;
  final ArmorType? targetArmor;

  const PlayCard({
    required super.playerId,
    required this.cardInstanceId,
    this.targetPlayerId,
    this.targetArmor,
  });

  @override
  String toString() => 'PlayCard($playerId, $cardInstanceId'
      '${targetPlayerId != null ? ' -> $targetPlayerId' : ''}'
      '${targetArmor != null ? ' (${targetArmor!.name})' : ''})';
}

/// Discard one card from hand: used both for end-of-turn hand-limit
/// discards and for event-driven discards (e.g. Wilderness Season). Always
/// an explicit action from the affected player, never automatic.
final class DiscardCard extends GameAction {
  final String cardInstanceId;

  const DiscardCard({required super.playerId, required this.cardInstanceId});

  @override
  String toString() => 'DiscardCard($playerId, $cardInstanceId)';
}

/// End the acting player's turn, advancing to the next player.
final class EndTurn extends GameAction {
  const EndTurn({required super.playerId});

  @override
  String toString() => 'EndTurn($playerId)';
}

/// Respond to a [PendingInterrupt] by playing a defense card from hand.
/// Valid from the current defender at any time during the interrupt, and
/// from any other player while `fellowshipRequested` is true (per the
/// Fellowship ruling: helping discards a defense card on the defender's
/// behalf).
final class DeclareDefense extends GameAction {
  final String cardInstanceId;

  const DeclareDefense({
    required super.playerId,
    required this.cardInstanceId,
  });

  @override
  String toString() => 'DeclareDefense($playerId, $cardInstanceId)';
}

/// Decline to defend against the current [PendingInterrupt]; the attack
/// resolves normally.
final class DeclineDefense extends GameAction {
  const DeclineDefense({required super.playerId});

  @override
  String toString() => 'DeclineDefense($playerId)';
}
