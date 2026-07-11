import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme/armor_up_colors.dart';

/// Per-badge vignette: lighter at the icon's center, darkening toward
/// the badge's own corners, so each armor piece reads as sitting in a
/// small recessed slot instead of a flat color fill - same idea as
/// _VignetteBoardBackground in game_screen.dart, but scoped to one
/// badge instead of the whole screen. Center tone matches the old flat
/// ArmorUpColors.cardBackground fill so this is a pure depth addition,
/// not a base color change.
const _badgeVignette = RadialGradient(
  center: Alignment.center,
  radius: 0.85,
  colors: [ArmorUpColors.cardBackground, Colors.black],
  stops: [0.35, 1.0],
);

IconData iconForArmor(ArmorType type) => switch (type) {
  ArmorType.helmet => Icons.sports_motorsports,
  ArmorType.breastplate => Icons.shield,
  ArmorType.shield => Icons.security,
  ArmorType.sword => Icons.gavel,
  ArmorType.belt => Icons.horizontal_rule,
  ArmorType.shoes => Icons.directions_walk,
};

/// Real pixel-art icon for an armor piece, cropped from the Tiny Swords
/// asset pack's armor_row.png reference sheet and hand-recolored to a
/// consistent silver/steel tone (all 6 pieces). All wired.
String? armorIconAssetPath(ArmorType type) => switch (type) {
  ArmorType.helmet => 'assets/armor/helmet.png',
  ArmorType.breastplate => 'assets/armor/breastplate.png',
  ArmorType.shield => 'assets/armor/shield.png',
  ArmorType.sword => 'assets/armor/sword.png',
  ArmorType.belt => 'assets/armor/belt.png',
  ArmorType.shoes => 'assets/armor/shoes.png',
};

/// Renders [armorIconAssetPath]'s pixel art when available, falling
/// back to [iconForArmor]'s Material icon otherwise (same fallback
/// pattern as the card medallions in card_widget.dart). Condition
/// mainly reads via [ArmorBadge]'s border/glow, but a Lost piece also
/// darkens the icon itself toward charcoal via [_lostFilter] - the
/// silver art alone didn't read as "broken/gone" without it, since the
/// border color change is easy to miss at a glance.
class _ArmorIcon extends StatelessWidget {
  final ArmorType type;
  final Color fallbackColor;
  final double size;
  final ArmorCondition condition;

  const _ArmorIcon({
    required this.type,
    required this.fallbackColor,
    required this.size,
    required this.condition,
  });

  /// Desaturates and crushes brightness down toward near-black charcoal
  /// rather than a flat opacity fade, so the icon reads as "cold,
  /// lifeless metal" instead of just a see-through version of the
  /// normal icon. 0.10 per channel (was 0.25) - the lighter version
  /// still read as a slightly-dim silver icon rather than a genuinely
  /// dark/broken one.
  static const _lostFilter = ColorFilter.matrix(<double>[
    0.10, 0.10, 0.10, 0, 0,
    0.10, 0.10, 0.10, 0, 0,
    0.10, 0.10, 0.10, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  /// Same desaturate-and-darken-toward-charcoal treatment as
  /// [_lostFilter], just a touch lighter (0.18 vs. Lost's 0.10) so
  /// Weakened sits close to Lost's near-black shading rather than a
  /// clearly-brighter midpoint - the two conditions should read as
  /// "almost as dark," with Strong's full brightness as the one clear
  /// outlier, not three evenly-spaced steps.
  static const _weakenedFilter = ColorFilter.matrix(<double>[
    0.18, 0.18, 0.18, 0, 0,
    0.18, 0.18, 0.18, 0, 0,
    0.18, 0.18, 0.18, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final assetPath = armorIconAssetPath(type);

    final Widget child;
    if (assetPath == null) {
      child = Icon(iconForArmor(type), color: fallbackColor, size: size);
    } else {
      child = Image.asset(
        assetPath,
        width: size,
        height: size,
        filterQuality: FilterQuality.none,
      );
    }

    return switch (condition) {
      ArmorCondition.lost => ColorFiltered(
        colorFilter: _lostFilter,
        child: child,
      ),
      ArmorCondition.weakened => ColorFiltered(
        colorFilter: _weakenedFilter,
        child: child,
      ),
      ArmorCondition.strong => child,
    };
  }
}

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
            gradient: _badgeVignette,
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
          padding: const EdgeInsets.all(3),
          child: _ArmorIcon(
            type: piece.type,
            fallbackColor: displayColor,
            size: 26,
            condition: piece.condition,
          ),
        ),
      );
    }

    // The icon alone is enough to identify the piece, and the border/
    // glow color alone is enough to identify its condition - a name
    // label and a condition label were both redundant with information
    // already on screen, so this now matches the compact variant's
    // simpler icon-fills-the-badge layout instead of stacking text
    // under a small icon.
    return InkWell(
      onTap: selectable ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: _badgeVignette,
          border: Border.all(color: color, width: selected ? 3 : 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6)]
              : null,
        ),
        child: _ArmorIcon(
          type: piece.type,
          fallbackColor: isLost ? color.withValues(alpha: 0.6) : color,
          size: 44,
          condition: piece.condition,
        ),
      ),
    );
  }
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
