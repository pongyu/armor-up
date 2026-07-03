import 'armor.dart';
import 'card.dart';

/// A single attack awaiting resolution: either the defender may respond
/// with a defense card, or (after a failed/absent Fellowship request) it
/// is about to land.
///
/// Modeled as explicit engine state (not a UI dialog) so a future network
/// layer can drive the same interrupt flow across clients: while
/// [GameState.pendingInterrupt] is non-null, [applyAction] only accepts
/// defense-related actions from the defender (and, during a Fellowship
/// request, from other players) plus [DeclineDefense].
///
/// Reflection chains: when It Is Written reflects an attack, the engine
/// replaces this record with a new [PendingAttack] whose `attackerId` and
/// `defenderId` are swapped, so the new defender goes through the same
/// defense window (including reflecting again).
final class PendingAttack {
  /// The attack card being resolved.
  final String attackCardDefId;

  /// A fresh instance id is not needed for resolution (the card already
  /// left the attacker's hand into the discard pile before this record is
  /// created), but we keep it for event logging / animation continuity.
  final String attackCardInstanceId;

  final String attackerId;
  final String defenderId;

  /// The specific armor piece this attack resolves against. Chosen at
  /// play time (for [TargetRule.anyPieceOnPlayer]) or implied by the card
  /// definition (for [TargetRule.specificArmorOnPlayer]).
  final ArmorType targetArmor;

  /// True for Goliath's Taunt: a double hit (Strong -> Lost directly) if
  /// it lands, and reflects at full strength (still a double hit) if
  /// mirrored by It Is Written.
  final bool isDoubleHit;

  /// Non-null while a Fellowship request is outstanding: any player other
  /// than [defenderId] who has not yet declined (see [helpersDeclined]) may
  /// discard a defense card to block on the defender's behalf. Once every
  /// other player has declined, the request is over and [defenderId] still
  /// gets to play their own defense card before the attack lands.
  final bool fellowshipRequested;

  /// Ids of players who have already declined to help during the current
  /// Fellowship request. Only meaningful while [fellowshipRequested] is
  /// true; reset (empty) otherwise.
  final Set<String> helpersDeclined;

  const PendingAttack({
    required this.attackCardDefId,
    required this.attackCardInstanceId,
    required this.attackerId,
    required this.defenderId,
    required this.targetArmor,
    this.isDoubleHit = false,
    this.fellowshipRequested = false,
    this.helpersDeclined = const {},
  });

  PendingAttack copyWith({
    String? attackCardDefId,
    String? attackCardInstanceId,
    String? attackerId,
    String? defenderId,
    ArmorType? targetArmor,
    bool? isDoubleHit,
    bool? fellowshipRequested,
    Set<String>? helpersDeclined,
  }) =>
      PendingAttack(
        attackCardDefId: attackCardDefId ?? this.attackCardDefId,
        attackCardInstanceId:
            attackCardInstanceId ?? this.attackCardInstanceId,
        attackerId: attackerId ?? this.attackerId,
        defenderId: defenderId ?? this.defenderId,
        targetArmor: targetArmor ?? this.targetArmor,
        isDoubleHit: isDoubleHit ?? this.isDoubleHit,
        fellowshipRequested:
            fellowshipRequested ?? this.fellowshipRequested,
        helpersDeclined: helpersDeclined ?? this.helpersDeclined,
      );

  /// The reflected form of this attack: same card/strength, attacker and
  /// defender swapped, any outstanding Fellowship request cleared.
  PendingAttack reflected() => PendingAttack(
        attackCardDefId: attackCardDefId,
        attackCardInstanceId: attackCardInstanceId,
        attackerId: defenderId,
        defenderId: attackerId,
        targetArmor: targetArmor,
        isDoubleHit: isDoubleHit,
        fellowshipRequested: false,
      );

  @override
  String toString() => 'PendingAttack($attackCardDefId, '
      '$attackerId -> $defenderId, ${targetArmor.name}, '
      'double=$isDoubleHit, fellowship=$fellowshipRequested, '
      'declined=$helpersDeclined)';
}

/// Reserved type alias kept for readability at call sites; currently
/// [PendingAttack] is the only kind of pending interrupt.
typedef PendingInterrupt = PendingAttack;
