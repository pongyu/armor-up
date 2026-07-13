import 'dart:math' as math;

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

/// Renders [armorIconAssetPath]'s pixel art when available, falling back
/// to [iconForArmor]'s Material icon otherwise (same fallback pattern as
/// the card medallions in card_widget.dart), plus the condition's overlay
/// glyph (crack for Weakened, X for Lost) painted on top.
///
/// DESIGN REVERSAL: the three conditions used to be tuned to read as
/// "almost as dark" (Weakened and Lost both crushed toward near-black,
/// differing only by a few percent brightness) on the theory that Strong
/// should be the one clear outlier. Playtesting showed players simply
/// could not tell Weakened and Lost apart at a glance - the three states
/// carry different strategic meanings (healthy / needs help soon /
/// needs a full restore card) and must be maximally distinct, not
/// minimally distinct-from-Strong. Every state now differs on three
/// independent channels - border color ([colorForCondition]), icon
/// tint/brightness (below), and overlay glyph (see
/// [_ArmorOverlayPainter]) - so the signal survives even a tiny compact
/// badge or a color-blind viewer who can't rely on hue alone.
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

  /// Dark, heavily desaturated silhouette - "empty but recoverable," not
  /// blank. ~22% per channel: inside the spec's 20-30% floor, clearly
  /// darker than Weakened's 60-70% so the two are unmistakable even
  /// without comparing borders, but not so close to 0% that the icon's
  /// silhouette disappears entirely (a fully blank slot reads as "nothing
  /// here" rather than "lost armor," which is the wrong message - Lost
  /// pieces can still be recovered).
  static const _lostFilter = ColorFilter.matrix(<double>[
    0.22, 0.22, 0.22, 0, 0,
    0.22, 0.22, 0.22, 0, 0,
    0.22, 0.22, 0.22, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  /// Desaturate-and-darken toward black (same family as [_lostFilter]),
  /// THEN add a flat amber tint via the matrix's translation column, so
  /// the result reads as "warm amber armor," not just a dimmer silver.
  /// Deliberately much lighter than [_lostFilter] (0.65 vs 0.22 base
  /// brightness) per the spec's explicit "NOT 18%, must stay clearly
  /// readable" - this is the biggest change from the old treatment,
  /// which crushed Weakened almost as dark as Lost. The translation
  /// column adds a fixed amber offset (independent of the source pixel's
  /// own brightness) on top of the darkened grayscale, which is why this
  /// reads as tinted rather than just "dark silver" - verified against
  /// the actual pixel art (assets/armor/*.png, bright silver/steel on
  /// transparent) rather than assumed to work.
  static const _weakenedFilter = ColorFilter.matrix(<double>[
    0.65, 0.65, 0.65, 0, 40,
    0.65, 0.65, 0.65, 0, 20,
    0.65, 0.65, 0.65, 0, 0,
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

    final tinted = switch (condition) {
      ArmorCondition.lost => ColorFiltered(colorFilter: _lostFilter, child: child),
      ArmorCondition.weakened => ColorFiltered(colorFilter: _weakenedFilter, child: child),
      // Strong: no filter at all - full, untouched brightness, per spec
      // ("remove the current darkening entirely for Strong").
      ArmorCondition.strong => child,
    };

    if (condition == ArmorCondition.strong) return tinted;

    return CustomPaint(
      size: Size(size, size),
      foregroundPainter: _ArmorOverlayPainter(condition: condition),
      child: tinted,
    );
  }
}

/// Paints the condition's overlay glyph on top of the icon: a jagged
/// crack for Weakened, a red X for Lost. Painted (not a new image asset)
/// so it scales cleanly with any badge size and works over every armor
/// icon without needing per-piece art. This is the primary cue at
/// compact/small sizes, where the border color and icon tint alone can
/// be hard to distinguish at a glance - the overlay's SHAPE (not just
/// its color) is what survives a quick glance or a color-blind viewer.
class _ArmorOverlayPainter extends CustomPainter {
  final ArmorCondition condition;

  const _ArmorOverlayPainter({required this.condition});

  @override
  void paint(Canvas canvas, Size size) {
    switch (condition) {
      case ArmorCondition.weakened:
        _paintCrack(canvas, size);
      case ArmorCondition.lost:
        _paintX(canvas, size);
      case ArmorCondition.strong:
        break;
    }
  }

  /// Two or three jagged dark strokes crossing the icon diagonally, like
  /// a crack in the armor. Dark rather than bright so it reads as damage
  /// (a shadowed gap), not as decoration.
  void _paintCrack(Canvas canvas, Size size) {
    final strokeWidth = (size.shortestSide * 0.06).clamp(1.0, 3.0);
    final paint = Paint()
      ..color = const Color(0xFF1A1610)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // A single jagged line from upper-left-ish to lower-right-ish, built
    // from a handful of zig-zag points so it reads as a fracture rather
    // than a straight scratch. Coordinates are fractions of the icon
    // size so the crack scales with the badge.
    final path = Path()
      ..moveTo(w * 0.30, h * 0.12)
      ..lineTo(w * 0.45, h * 0.34)
      ..lineTo(w * 0.32, h * 0.48)
      ..lineTo(w * 0.52, h * 0.66)
      ..lineTo(w * 0.40, h * 0.80)
      ..lineTo(w * 0.58, h * 0.94);
    canvas.drawPath(path, paint);

    // A short second branch off the main crack, reinforcing the
    // "shattered" read without adding a whole second full-length line.
    final branch = Path()
      ..moveTo(w * 0.32, h * 0.48)
      ..lineTo(w * 0.18, h * 0.58);
    canvas.drawPath(branch, paint..strokeWidth = strokeWidth * 0.75);
  }

  /// A red X, corner-to-corner with a slight inset, marking the slot as
  /// lost. Two strokes only, per spec.
  void _paintX(Canvas canvas, Size size) {
    final strokeWidth = (size.shortestSide * 0.09).clamp(1.5, 4.0);
    final paint = Paint()
      ..color = const Color(0xFFC23B3B)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const inset = 0.16;
    final w = size.width;
    final h = size.height;

    canvas.drawLine(
      Offset(w * inset, h * inset),
      Offset(w * (1 - inset), h * (1 - inset)),
      paint,
    );
    canvas.drawLine(
      Offset(w * (1 - inset), h * inset),
      Offset(w * inset, h * (1 - inset)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArmorOverlayPainter oldDelegate) =>
      oldDelegate.condition != condition;
}

Color colorForCondition(ArmorCondition condition) => switch (condition) {
  ArmorCondition.strong => ArmorUpColors.armorStrong,
  ArmorCondition.weakened => ArmorUpColors.armorWeakened,
  ArmorCondition.lost => ArmorUpColors.armorLost,
};

/// Small marker shown on a badge whose piece is the target of an active
/// Fasting (see [PlayerState.fastingRestoreTarget]). Deliberately visible
/// on every viewer's copy of the row it appears in - opponents seeing
/// which piece is about to heal is the counterplay window Fasting's
/// delayed-restore timing exists to create, not a leak to hide.
///
/// A small pulsing dot rather than a static glyph, so it reads as "in
/// progress" / "still ticking" at a glance, distinct from the crack/X
/// overlays (which mark a fixed condition, not an ongoing process).
class _FastingMarker extends StatefulWidget {
  final double size;

  const _FastingMarker({required this.size});

  @override
  State<_FastingMarker> createState() => _FastingMarkerState();
}

class _FastingMarkerState extends State<_FastingMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = reduceMotion ? 1.0 : _controller.value;
        return Opacity(opacity: 0.5 + t * 0.5, child: child);
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ArmorUpColors.goldAccent,
          border: Border.all(color: ArmorUpColors.cardStroke, width: 1),
        ),
        child: Icon(Icons.hourglass_bottom, size: widget.size * 0.7, color: ArmorUpColors.cardStroke),
      ),
    );
  }
}

/// A single armor piece badge: icon, short name, and condition, tappable
/// when used as an attack/restore target picker. Pass [compact] for the
/// small icon-only variant used in glanceable per-player rows (e.g. the
/// center player-list panel on the landscape board), where showing full
/// name/condition text for every piece of every player would be too much
/// detail - the detailed view lives in the active player's armor grid.
class ArmorBadge extends StatefulWidget {
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

  /// True when this exact piece is the target of the owning player's
  /// active Fasting ([PlayerState.fastingRestoreTarget] == this piece's
  /// type). Shows [_FastingMarker]; the caller is responsible for
  /// clearing this once the fast completes or the player is eliminated
  /// (both already clear `fastingRestoreTarget` on the engine side, so
  /// this simply mirrors that field - see callers in game_screen.dart).
  final bool fasting;

  const ArmorBadge({
    super.key,
    required this.piece,
    this.selectable = false,
    this.selected = false,
    this.onTap,
    this.compact = false,
    this.muted = false,
    this.fasting = false,
  });

  @override
  State<ArmorBadge> createState() => _ArmorBadgeState();
}

class _ArmorBadgeState extends State<ArmorBadge> with TickerProviderStateMixin {
  ArmorCondition? _previousCondition;

  /// Damage (Strong->Weakened, Weakened->Lost): quick shake + the new
  /// overlay fading in. Restore (->Strong): the old overlay fading out +
  /// a brief gold glow pulse. Both driven purely from a per-widget
  /// condition diff (previous build's condition vs. this build's), not
  /// from any engine event - the existing widget rebuild on every state
  /// change is enough of a signal.
  late final AnimationController _shakeController;
  late final AnimationController _glowController;

  /// Eligible-but-unselected badges get a slow, subtle pulsing glow
  /// during target selection so the live choices are easy to spot at a
  /// glance without being as loud as the selected-state glow. Runs
  /// continuously while eligible (not one-shot like shake/restore), so
  /// it lives on its own always-repeating controller instead of being
  /// folded into _glowController.
  late final AnimationController _eligiblePulseController;

  @override
  void initState() {
    super.initState();
    _previousCondition = widget.piece.condition;
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _eligiblePulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ArmorBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _previousCondition;
    final current = widget.piece.condition;
    if (previous != null && previous != current) {
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      if (!reduceMotion) {
        final gotWorse = _severity(current) > _severity(previous);
        if (gotWorse) {
          _shakeController.forward(from: 0);
        } else {
          _glowController.forward(from: 0);
        }
      }
    }
    _previousCondition = current;
  }

  int _severity(ArmorCondition condition) => switch (condition) {
    ArmorCondition.strong => 0,
    ArmorCondition.weakened => 1,
    ArmorCondition.lost => 2,
  };

  @override
  void dispose() {
    _shakeController.dispose();
    _glowController.dispose();
    _eligiblePulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final piece = widget.piece;
    final selectable = widget.selectable;
    final selected = widget.selected;
    final onTap = widget.onTap;
    final compact = widget.compact;
    final muted = widget.muted;

    final color = colorForCondition(piece.condition);
    final displayColor = muted ? color.withValues(alpha: 0.35) : color;
    final badgeSize = compact ? 32.0 : 52.0;
    final iconSize = compact ? 26.0 : 44.0;
    final borderRadius = BorderRadius.circular(8);

    // Eligible-and-not-yet-selected: pulse a subtle glow so the live
    // choices are easy to spot without being as loud as the selected
    // state. Muted/ineligible badges never pulse; selected badges use
    // the existing static (non-animated) stronger glow instead so the
    // two states stay visually distinct from each other.
    final showEligiblePulse = selectable && !selected && !muted;

    Widget badge = AnimatedBuilder(
      animation: Listenable.merge([_shakeController, _glowController, _eligiblePulseController]),
      builder: (context, child) {
        final shake = _shakeShift(_shakeController.value);
        final glowT = _glowController.value; // 0..1..0 handled by curve below
        final restoreGlowAlpha = _restoreGlowAlpha(glowT);
        final pulseAlpha = showEligiblePulse ? _eligiblePulseAlpha(_eligiblePulseController.value) : 0.0;

        final boxShadows = <BoxShadow>[
          if (selected)
            BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: compact ? 4 : 6),
          if (restoreGlowAlpha > 0)
            BoxShadow(
              color: ArmorUpColors.goldAccent.withValues(alpha: restoreGlowAlpha),
              blurRadius: compact ? 6 : 10,
              spreadRadius: 1,
            ),
          if (pulseAlpha > 0)
            BoxShadow(
              color: ArmorUpColors.goldAccent.withValues(alpha: pulseAlpha),
              blurRadius: compact ? 5 : 8,
            ),
        ];

        return Transform.translate(
          offset: Offset(shake, 0),
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              gradient: _badgeVignette,
              border: Border.all(color: displayColor, width: selected ? 3 : 2),
              borderRadius: borderRadius,
              boxShadow: boxShadows.isEmpty ? null : boxShadows,
            ),
            padding: EdgeInsets.all(compact ? 3 : 4),
            child: child,
          ),
        );
      },
      child: _ArmorIcon(
        type: piece.type,
        fallbackColor: displayColor,
        size: iconSize,
        condition: piece.condition,
      ),
    );

    if (widget.fasting) {
      badge = Stack(
        clipBehavior: Clip.none,
        children: [
          badge,
          Positioned(
            top: -4,
            right: -4,
            child: _FastingMarker(size: compact ? 14 : 18),
          ),
        ],
      );
    }

    return InkWell(
      onTap: selectable ? onTap : null,
      borderRadius: borderRadius,
      child: badge,
    );
  }

  /// A quick left-right-left wobble, not a smooth sine - reads as a
  /// sharper "hit" than an eased oscillation would.
  double _shakeShift(double t) {
    if (t <= 0 || t >= 1) return 0;
    final wobble = math.sin(t * math.pi * 4) * (1 - t);
    return wobble * 4;
  }

  /// Gold glow pulses in then back out over the animation's full
  /// duration - a calm "bloom and fade," deliberately not a sharp flash,
  /// to contrast with the shake's abruptness per the spec ("Calm, not
  /// flashy - deliberate contrast with damage").
  double _restoreGlowAlpha(double t) {
    if (t <= 0 || t >= 1) return 0;
    return math.sin(t * math.pi) * 0.7;
  }

  double _eligiblePulseAlpha(double t) => 0.35 + t * 0.30;
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
              fasting: player.fastingRestoreTarget == piece.type,
            ),
          ),
      ],
    );
  }
}
