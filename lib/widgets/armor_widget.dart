import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme/armor_up_colors.dart';

IconData iconForArmor(ArmorType type) => switch (type) {
      ArmorType.helmet => Icons.sports_motorsports,
      ArmorType.breastplate => Icons.shield,
      ArmorType.shield => Icons.security,
      ArmorType.sword => Icons.gavel,
      ArmorType.belt => Icons.horizontal_rule,
      ArmorType.shoes => Icons.directions_walk,
    };

Color colorForCondition(ArmorCondition condition) => switch (condition) {
      ArmorCondition.strong => ArmorUpColors.armorStrong,
      ArmorCondition.weakened => ArmorUpColors.armorWeakened,
      ArmorCondition.lost => ArmorUpColors.armorLost,
    };

/// A single armor piece badge: icon, short name, and condition, tappable
/// when used as an attack/restore target picker.
class ArmorBadge extends StatelessWidget {
  final ArmorPiece piece;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;

  const ArmorBadge({
    super.key,
    required this.piece,
    this.selectable = false,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorForCondition(piece.condition);
    final isLost = piece.condition == ArmorCondition.lost;

    return InkWell(
      onTap: selectable ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: ArmorUpColors.cardBackground,
          border: Border.all(color: color, width: selected ? 3 : 2),
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6)]
              : null,
        ),
        child: Column(
          children: [
            Icon(iconForArmor(piece.type), color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              _shortName(piece.type),
              style: TextStyle(
                fontSize: 10,
                color: ArmorUpColors.cardStroke.withValues(alpha: isLost ? 0.5 : 0.9),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            const SizedBox(height: 2),
            Text(
              _conditionLabel(piece.condition),
              style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  String _shortName(ArmorType type) => switch (type) {
        ArmorType.helmet => 'Helmet',
        ArmorType.breastplate => 'Breastplate',
        ArmorType.shield => 'Shield',
        ArmorType.sword => 'Sword',
        ArmorType.belt => 'Belt',
        ArmorType.shoes => 'Shoes',
      };

  String _conditionLabel(ArmorCondition condition) => switch (condition) {
        ArmorCondition.strong => 'STRONG',
        ArmorCondition.weakened => 'WEAK',
        ArmorCondition.lost => 'LOST',
      };
}

/// Default per-piece selectability: excludes Lost pieces, which is correct
/// for attack cards (you can't hit an already-lost piece). Restore cards
/// with different rules (e.g. Armor Bearer targets only Lost pieces) should
/// pass an override to [ArmorRow.isConditionSelectable].
bool defaultIsConditionSelectable(ArmorCondition condition) =>
    condition != ArmorCondition.lost;

/// A row of all six armor badges for one player.
class ArmorRow extends StatelessWidget {
  final PlayerState player;
  final bool selectable;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType>? onSelect;

  /// Further restricts which pieces are selectable based on their current
  /// condition (e.g. a restore card may only target a Lost or Weakened
  /// piece). Defaults to excluding Lost pieces, which is correct for
  /// attack cards; pass an override for cards with different rules.
  final bool Function(ArmorCondition condition) isConditionSelectable;

  const ArmorRow({
    super.key,
    required this.player,
    this.selectable = false,
    this.selectedArmor,
    this.onSelect,
    this.isConditionSelectable = defaultIsConditionSelectable,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final piece in player.armor)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ArmorBadge(
                piece: piece,
                selectable: selectable && isConditionSelectable(piece.condition),
                selected: selectedArmor == piece.type,
                onTap: onSelect == null ? null : () => onSelect!(piece.type),
              ),
            ),
        ],
      ),
    );
  }
}
