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

  /// True once any of this player's armor has ever dropped below Strong.
  /// Every player starts at full Strong, so the restoration win condition
  /// ("all 6 Strong at the start of your turn") only counts once it is a
  /// genuine comeback - i.e. this flag must be true - not simply an
  /// untouched starting state. Never reset back to false once set.
  final bool wasEverDamaged;

  const PlayerState({
    required this.id,
    required this.name,
    required this.armor,
    required this.hand,
    this.isFasting = false,
    this.fastingScheduled = false,
    this.wasEverDamaged = false,
  });

  bool get isEliminated =>
      armor.every((piece) => piece.condition == ArmorCondition.lost);

  bool get isFullyRestored =>
      wasEverDamaged && armor.every((piece) => piece.condition == ArmorCondition.strong);

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
    bool? wasEverDamaged,
  }) =>
      PlayerState(
        id: id ?? this.id,
        name: name ?? this.name,
        armor: armor ?? this.armor,
        hand: hand ?? this.hand,
        isFasting: isFasting ?? this.isFasting,
        fastingScheduled: fastingScheduled ?? this.fastingScheduled,
        wasEverDamaged: wasEverDamaged ?? this.wasEverDamaged,
      );

  /// Returns a copy with [type]'s condition replaced. Marks
  /// [wasEverDamaged] once any piece first drops below Strong.
  PlayerState withArmorCondition(ArmorType type, ArmorCondition condition) {
    final updated = [
      for (final piece in armor)
        if (piece.type == type) piece.copyWith(condition: condition) else piece,
    ];
    final damaged = wasEverDamaged || condition != ArmorCondition.strong;
    return copyWith(armor: updated, wasEverDamaged: damaged);
  }

  @override
  String toString() => 'PlayerState($id, ${armor.length} armor, '
      '${hand.length} cards, fasting=$isFasting)';
}
