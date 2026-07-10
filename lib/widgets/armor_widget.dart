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
/// when used as an attack/restore target picker. Pass [compact] for the
/// small icon-only variant used in glanceable per-player rows (e.g. the
/// center player-list panel on the landscape board), where showing full
/// name/condition text for every piece of every player would be too much
/// detail - the detailed view lives in the active player's armor grid.
class ArmorBadge extends StatelessWidget {
  final ArmorPiece piece;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  /// True while a target-selection step is in progress table-wide but this
  /// particular badge isn't a legal choice (wrong player's row, or its
  /// condition is excluded) - it mutes down so only the actually-selectable
  /// badges read as actionable, instead of every player's row looking
  /// equally lit regardless of whose turn it is to be picked.
  final bool muted;

  const ArmorBadge({
    super.key,
    required this.piece,
    this.selectable = false,
    this.selected = false,
    this.onTap,
    this.compact = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorForCondition(piece.condition);
    final isLost = piece.condition == ArmorCondition.lost;

    if (compact) {
      final displayColor = muted ? color.withValues(alpha: 0.35) : color;

      return InkWell(
        onTap: selectable ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: ArmorUpColors.cardBackground,
            border: Border.all(color: displayColor, width: selected ? 3 : 2),
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.55),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Icon(iconForArmor(piece.type), color: displayColor, size: 18),
        ),
      );
    }

    return InkWell(
      onTap: selectable ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: ArmorUpColors.cardBackground,
          border: Border.all(color: color, width: selected ? 3 : 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6)]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconForArmor(piece.type), color: color, size: 18),
            const SizedBox(height: 3),
            Text(
              _shortName(piece.type),
              style: TextStyle(
                fontSize: 8,
                color: ArmorUpColors.fontColor.withValues(
                  alpha: isLost ? 0.5 : 0.9,
                ),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              _conditionLabel(piece.condition),
              style: TextStyle(
                fontSize: 8,
                color: color,
                fontWeight: FontWeight.bold,
              ),
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

/// A row of all six armor badges for one player. Pass [compact] for the
/// small icon-only badges used in glanceable per-player rows.
class ArmorRow extends StatelessWidget {
  final PlayerState player;
  final bool selectable;
  final ArmorType? selectedArmor;
  final ValueChanged<ArmorType>? onSelect;
  final bool compact;

  /// True while a target-selection step is in progress table-wide but this
  /// whole row isn't the eligible one (e.g. a different opponent than the
  /// one already chosen as the target player) - every badge in the row
  /// mutes down together rather than looking as actionable as the real
  /// target's row.
  final bool muted;

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
    this.compact = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final piece in player.armor)
          Padding(
            padding: EdgeInsets.only(right: compact ? 5 : 6),
            child: ArmorBadge(
              piece: piece,
              selectable: selectable && isConditionSelectable(piece.condition),
              // Gated on `selectable` (this row's own eligibility), not
              // just a type match: `selectedArmor` is a single shared
              // ArmorType value, so without this every other player's
              // same-type piece (e.g. every Breastplate) would light up
              // as "selected" too, even on rows that aren't the actual
              // target.
              selected: selectable && selectedArmor == piece.type,
              onTap: onSelect == null ? null : () => onSelect!(piece.type),
              compact: compact,
              muted:
                  muted ||
                  (selectable && !isConditionSelectable(piece.condition)),
            ),
          ),
      ],
    );
  }
}
