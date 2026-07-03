/// The six pieces of armor from Ephesians 6, each held by every player.
enum ArmorType {
  helmet,
  breastplate,
  shield,
  sword,
  belt,
  shoes;

  String get displayName => switch (this) {
        ArmorType.helmet => 'Helmet of Salvation',
        ArmorType.breastplate => 'Breastplate of Righteousness',
        ArmorType.shield => 'Shield of Faith',
        ArmorType.sword => 'Sword of the Spirit',
        ArmorType.belt => 'Belt of Truth',
        ArmorType.shoes => 'Shoes of Peace',
      };
}

/// The condition of a single armor piece. Attacks step a piece down one
/// level per hit; [lost] pieces cannot be hit again (the attack has no
/// further effect on an already-lost piece).
enum ArmorCondition {
  strong,
  weakened,
  lost;

  /// Returns the condition after taking one hit, floored at [lost].
  ArmorCondition stepDown() => switch (this) {
        ArmorCondition.strong => ArmorCondition.weakened,
        ArmorCondition.weakened => ArmorCondition.lost,
        ArmorCondition.lost => ArmorCondition.lost,
      };
}

/// One armor piece belonging to a player: its type and current condition.
final class ArmorPiece {
  final ArmorType type;
  final ArmorCondition condition;

  const ArmorPiece({required this.type, required this.condition});

  ArmorPiece copyWith({ArmorCondition? condition}) =>
      ArmorPiece(type: type, condition: condition ?? this.condition);

  @override
  bool operator ==(Object other) =>
      other is ArmorPiece && other.type == type && other.condition == condition;

  @override
  int get hashCode => Object.hash(type, condition);

  @override
  String toString() => 'ArmorPiece(${type.name}: ${condition.name})';
}

/// The full set of six armor pieces, all [ArmorCondition.strong], in fixed
/// display order.
List<ArmorPiece> startingArmorSet() => [
      for (final type in ArmorType.values)
        ArmorPiece(type: type, condition: ArmorCondition.strong),
    ];
