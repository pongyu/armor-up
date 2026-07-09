import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme/armor_up_colors.dart';
import 'card_display.dart';

/// Optional background texture for the card face and description panel.
/// Until the user drops a real file at this path, [_texturedFill] falls
/// back cleanly to the flat [ArmorUpColors.cardBackground] color - see
/// assets/textures/README.md for the art spec.
const _parchmentTextureAssetPath = 'assets/textures/parchment.png';

Color colorForCardType(CardType type) => switch (type) {
  CardType.attack => ArmorUpColors.bannerAttack,
  CardType.defense => ArmorUpColors.bannerDefense,
  CardType.restore => ArmorUpColors.bannerRestore,
  CardType.event => ArmorUpColors.bannerEvent,
};

String labelForCardType(CardType type) => switch (type) {
  CardType.attack => 'Trial',
  CardType.defense => 'Defense',
  CardType.restore => 'Restore',
  CardType.event => 'Event',
};

String describeEffect(CardDef def) {
  final target = switch (def.targetRule) {
    TargetRule.specificArmorOnPlayer =>
      'Weaken/hit ${def.fixedTarget!.displayName}',
    TargetRule.anyPieceOnPlayer =>
      def.effect == EffectPrimitive.doubleHit
          ? 'Hits any piece twice'
          : 'Weaken/hit any piece',
    TargetRule.singlePlayer => 'Steal a random card',
    TargetRule.ownArmorPiece => switch (def.effect) {
      EffectPrimitive.restoreOneStep => 'Weakened -> Strong on your piece',
      EffectPrimitive.restoreFullyFromLost => 'Lost -> Strong on your piece',
      EffectPrimitive.skipNextTurnAndRestore =>
        'Skip your next turn; fully restore one piece',
      _ => '',
    },
    TargetRule.allPlayers => switch (def.effect) {
      EffectPrimitive.allWeakenedToLost =>
        "All players' Weakened pieces become Lost",
      EffectPrimitive.allDiscardOne => 'Every player discards one card',
      _ => '',
    },
    TargetRule.none => switch (def.effect) {
      EffectPrimitive.blockAttack => 'Block any attack',
      EffectPrimitive.reflectAttack => 'Block and reflect an attack',
      EffectPrimitive.fellowshipRequest => 'Ask the table to block for you',
      _ => '',
    },
  };
  return target;
}

/// A textured fill: one piece of parchment stretched/cropped to cover the
/// whole area (not tiled - a repeating tile made the crop's crease mark
/// read as an obvious wallpaper pattern) over the flat
/// [ArmorUpColors.cardBackground] color if the asset exists, or just the
/// flat color if it doesn't (no crash, no broken-image icon - the asset
/// is optional until the user supplies one per assets/textures/README.md).
BoxDecoration _texturedFill({BorderRadiusGeometry? borderRadius}) {
  return BoxDecoration(
    color: ArmorUpColors.cardBackground,
    borderRadius: borderRadius,
    image: DecorationImage(
      image: const AssetImage(_parchmentTextureAssetPath),
      fit: BoxFit.cover,
      onError:
          (error, stackTrace) {}, // Missing asset: flat color shows through.
    ),
  );
}

/// A single card: parchment frame, a circular illustration medallion, a
/// name banner that overlaps the medallion's bottom edge, and an inset
/// parchment description panel with effect text and verse reference.
///
/// The card frame itself (the outer border) is drawn with layered Flutter
/// borders/shadows rather than a hand-drawn ornamental asset - there's no
/// per-card variation to it, so if a nine-slice frame PNG is produced
/// later, it can replace [_CardFrame]'s decoration in one place without
/// touching the rest of this widget's layout.
class CardWidget extends StatelessWidget {
  static const double cardWidth = 130;
  static const double cardHeight = 186;

  final CardDef def;
  final bool selected;
  final VoidCallback? onTap;

  const CardWidget({
    super.key,
    required this.def,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final banner = colorForCardType(def.type);
    final spec = displaySpecFor(def.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: _CardFrame(
        selected: selected,
        accentColor: banner,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The medallion's diameter matches the description panel's
            // width (card width minus its horizontal margin), so both
            // read as the same size circle-vs-rectangle.
            const bannerHeight = 22.0;
            const topInset = 4.0;
            // Where the description panel's background starts: a bit
            // above the banner's bottom edge on purpose, so the medallion
            // visually overlaps down behind the banner and the panel's
            // top-left/right slivers, matching the reference card.
            const descriptionTop = 100.0;
            final medallionDiameter = constraints.maxWidth - 16;
            final bannerTop = topInset + medallionDiameter - bannerHeight / 2;
            final bannerBottom = bannerTop + bannerHeight;
            // The text itself must start below the banner's actual bottom
            // edge, not just some fixed offset from descriptionTop - the
            // panel's background can sit under the banner, but the text
            // can't, or it renders visually clipped by/under the banner.
            // Whatever vertical room that leaves for the text itself
            // (which can be tight for a long description on a
            // full-width medallion), _DescriptionPanel scales its own
            // font down to fit rather than needing exact pixel budgeting
            // here.
            final textTopPadding = bannerBottom - descriptionTop + 6;

            return Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: topInset,
                  child: _Medallion(spec: spec, diameter: medallionDiameter),
                ),
                Positioned(
                  top: descriptionTop,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _DescriptionPanel(
                    text: describeEffect(def),
                    verseRef: def.verseRef,
                    textTopPadding: textTopPadding,
                  ),
                ),
                Positioned(
                  top: bannerTop,
                  child: _NameBanner(
                    name: def.name,
                    color: banner,
                    height: bannerHeight,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Pixel-art nine-slice card border. A single 48x48 PNG: 12px corners
/// (drawn with pixelated stair-step edges, never stretched), 12px-thick
/// straight edge segments (stretched to fit the card's actual size), and
/// a fully transparent 24x24 center so the card's own content shows
/// through. See assets/cards/README.md for the art spec.
const _cardFrameAssetPath = 'assets/cards/card_frame.png';
const _cardFrameCenterSlice = Rect.fromLTRB(12, 12, 36, 36);

/// The card's outer parchment frame: flat fill, the pixel-art nine-slice
/// border on top, and a selection glow. Isolated from the content layout
/// so the frame art can be swapped without touching the rest of the card.
class _CardFrame extends StatelessWidget {
  final bool selected;
  final Color accentColor;
  final Widget child;

  const _CardFrame({
    required this.selected,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: CardWidget.cardWidth,
      height: CardWidget.cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          if (selected)
            BoxShadow(color: accentColor.withValues(alpha: 0.55), blurRadius: 8)
          else
            const BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 2),
            ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Padding matches the frame PNG's 12px corner inset (the part
          // of centerSlice that stays at native pixel size rather than
          // stretching), so content sits fully inside the border art
          // instead of being covered by or leaving a gap from it. Flat
          // color at this scale, not textured: the source crop is small
          // (64px) and stretching it across the whole card face would
          // look soft/blurry. The reference card's paper texture is
          // really only visible in the description panel anyway - see
          // _DescriptionPanel below.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(color: ArmorUpColors.cardBackground, child: child),
          ),
          // Nearest-neighbor, no smoothing - the frame is pixel art and
          // must not blur when the nine-slice edges stretch to fit the
          // card's actual size.
          const Image(
            image: AssetImage(_cardFrameAssetPath),
            centerSlice: _cardFrameCenterSlice,
            filterQuality: FilterQuality.none,
            fit: BoxFit.fill,
          ),
        ],
      ),
    );
  }
}

/// The circular illustration frame: a double-ring border around the art
/// (or placeholder icon), matching the reference card's medallion look.
class _Medallion extends StatelessWidget {
  final CardDisplaySpec spec;
  final double diameter;

  const _Medallion({required this.spec, required this.diameter});

  @override
  Widget build(BuildContext context) {
    final assetPath = spec.illustrationAssetPath;

    return Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ArmorUpColors.medallionRing,
      ),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          border: Border.fromBorderSide(
            BorderSide(color: ArmorUpColors.goldAccent, width: 1.5),
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: ClipOval(
          child: Container(
            color: ArmorUpColors.cardBackground,
            child: assetPath != null
                // Final art will be pixel art: never let default filtering
                // blur it on scale.
                ? Image.asset(
                    assetPath,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.none,
                  )
                : Center(
                    child: Icon(
                      spec.iconPlaceholder,
                      size: diameter * 0.45,
                      color: ArmorUpColors.cardStroke.withValues(alpha: 0.55),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The card name banner: a rounded pill that floats over the medallion's
/// bottom edge rather than spanning the card edge-to-edge.
class _NameBanner extends StatelessWidget {
  final String name;
  final Color color;
  final double height;

  const _NameBanner({
    required this.name,
    required this.color,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: height,
        maxWidth: CardWidget.cardWidth - 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: ArmorUpColors.goldAccent, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          maxLines: 1,
          style: const TextStyle(
            color: ArmorUpColors.fontColor,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            shadows: ArmorUpColors.titleOutline,
          ),
        ),
      ),
    );
  }
}

/// The description panel: light textured parchment (not the old dark
/// brown band) with dark text, reading as a raised/inset paper piece via
/// a drop shadow rather than a bordered box, matching the reference card.
///
/// [textTopPadding] pushes the text content down independently of the
/// panel's own bounds/background - the panel's top sliver deliberately
/// sits behind the medallion/banner overlap, but the readable text must
/// always clear the banner's bottom edge.
class _DescriptionPanel extends StatelessWidget {
  final String text;
  final String verseRef;
  final double textTopPadding;

  const _DescriptionPanel({
    required this.text,
    required this.verseRef,
    required this.textTopPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(6, textTopPadding, 6, 4),
      decoration: _texturedFill(borderRadius: BorderRadius.circular(6))
          .copyWith(
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
      // A long effect description (e.g. Pride's) can be taller than the
      // room left after the banner overlap eats into this panel -
      // FittedBox scales the whole text block down to fit rather than
      // needing exact pixel budgeting between the medallion/banner
      // overlap and the text underneath.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: CardWidget.cardWidth - 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: ArmorUpColors.cardStroke,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                verseRef,
                style: TextStyle(
                  fontSize: 7,
                  fontStyle: FontStyle.italic,
                  color: ArmorUpColors.cardStroke.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
