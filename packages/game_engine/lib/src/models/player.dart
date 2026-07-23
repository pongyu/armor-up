import 'armor.dart';
import 'card.dart';

/// One player's full public+private state. In Phase 1 (hotseat, single
/// process) hand contents are visible to the engine for all players at
/// once; the UI is responsible for hiding other players' hands during
/// pass-and-play. Phase 2's network layer will filter this per-recipient.
final class PlayerState {
  final String id;
  final String name;
  final List<ArmorPiece> armor;
  final List<CardInstance> hand;

  /// True during this player's own turn once it has come around, meaning
  /// they must skip the play step this turn (they still draw). Set by the
  /// engine when advancing turn order into a player who has
  /// [fastingScheduled], and cleared again once that turn ends.
  final bool isFasting;

  /// True from the moment this player plays Fasting until their next turn
  /// begins, at which point the engine converts it into [isFasting] for
  /// that single turn. Needed because Fasting is played mid-turn, but the
  /// skipped play step is the player's *next* turn, not the current one.
  final bool fastingScheduled;

  /// The armor piece chosen when Fasting was played, pending restoration
  /// until the fast is actually endured. Non-null from the moment Fasting
  /// is played until the end of the fasted turn, at which point the piece
  /// is restored to Strong (regardless of its condition at that moment -
  /// see `_endTurn` in engine.dart) and this is cleared. Public knowledge
  /// (not redacted over the network): seeing which piece an opponent is
  /// fasting for is part of the counterplay window Fasting now opens.
  final ArmorType? fastingRestoreTarget;

  /// True once this player has helped block another player's attack via a
  /// Fellowship request (see [EffectPrimitive.fellowshipRequest]). Consumed
  /// automatically to no-effect-block the next attack declared against this
  /// player - see `_beginAttack` in effects.dart - at which point it is
  /// cleared. Reciprocity for the help given: the shield rewards the
  /// helper directly rather than costing them a card for nothing.
  final bool isShielded;

  /// True once at least one of this player's armor pieces has ever reached
  /// [ArmorCondition.lost]. Every player starts at full Strong, so the
  /// restoration win condition ("all 6 Strong at the start of your turn")
  /// only counts once it is a genuine "brought low, then restored"
  /// comeback - i.e. this flag must be true - not simply an untouched
  /// starting state, and (per the threshold set after playtesting) not a
  /// single Weakened scratch patched up with one Renewal either. Never
  /// reset back to false once set.
  final bool wasEverBroken;

  const PlayerState({
    required this.id,
    required this.name,
    required this.armor,
    required this.hand,
    this.isFasting = false,
    this.fastingScheduled = false,
    this.fastingRestoreTarget,
    this.wasEverBroken = false,
    this.isShielded = false,
  });

  bool get isEliminated =>
      armor.every((piece) => piece.condition == ArmorCondition.lost);

  bool get isFullyRestored =>
      wasEverBroken && armor.every((piece) => piece.condition == ArmorCondition.strong);

  int get strongPieceCount =>
      armor.where((piece) => piece.condition == ArmorCondition.strong).length;

  int get lostPieceCount =>
      armor.where((piece) => piece.condition == ArmorCondition.lost).length;

  ArmorPiece armorOf(ArmorType type) =>
      armor.firstWhere((piece) => piece.type == type);

  PlayerState copyWith({
    String? id,
    String? name,
    List<ArmorPiece>? armor,
    List<CardInstance>? hand,
    bool? isFasting,
    bool? fastingScheduled,
    ArmorType? fastingRestoreTarget,
    bool clearFastingRestoreTarget = false,
    bool? wasEverBroken,
    bool? isShielded,
  }) =>
      PlayerState(
        id: id ?? this.id,
        name: name ?? this.name,
        armor: armor ?? this.armor,
        hand: hand ?? this.hand,
        isFasting: isFasting ?? this.isFasting,
        fastingScheduled: fastingScheduled ?? this.fastingScheduled,
        fastingRestoreTarget: clearFastingRestoreTarget
            ? null
            : (fastingRestoreTarget ?? this.fastingRestoreTarget),
        wasEverBroken: wasEverBroken ?? this.wasEverBroken,
        isShielded: isShielded ?? this.isShielded,
      );

  /// Returns a copy with [type]'s condition replaced. Marks
  /// [wasEverBroken] once any piece first reaches [ArmorCondition.lost].
  PlayerState withArmorCondition(ArmorType type, ArmorCondition condition) {
    final updated = [
      for (final piece in armor)
        if (piece.type == type) piece.copyWith(condition: condition) else piece,
    ];
    final broken = wasEverBroken || condition == ArmorCondition.lost;
    return copyWith(armor: updated, wasEverBroken: broken);
  }

  @override
  String toString() => 'PlayerState($id, ${armor.length} armor, '
      '${hand.length} cards, fasting=$isFasting)';
}
