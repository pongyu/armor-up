import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme/armor_up_colors.dart';
import 'card_display.dart';

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
    TargetRule.specificArmorOnPlayer => 'Weaken/hit ${def.fixedTarget!.displayName}',
    TargetRule.anyPieceOnPlayer =>
      def.effect == EffectPrimitive.doubleHit ? 'Hits any piece twice' : 'Weaken/hit any piece',
    TargetRule.singlePlayer => 'Steal a random card',
    TargetRule.ownArmorPiece => switch (def.effect) {
        EffectPrimitive.restoreOneStep => 'Weakened -> Strong on your piece',
        EffectPrimitive.restoreFullyFromLost => 'Lost -> Strong on your piece',
        EffectPrimitive.skipNextTurnAndRestore =>
          'Skip your next turn; fully restore one piece',
        _ => '',
      },
    TargetRule.allPlayers => switch (def.effect) {
        EffectPrimitive.allWeakenedToLost => "All players' Weakened pieces become Lost",
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

/// A single card in the warm illustrated style: parchment frame with a
/// double-border bevel, illustration box (placeholder icon until real art
/// is wired up in [cardDisplaySpecs]), type-colored name banner, and a
/// description panel with effect text and verse reference.
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
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: ArmorUpColors.cardBackground,
          border: Border.all(
            color: selected ? banner : ArmorUpColors.cardStroke,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: banner.withValues(alpha: 0.55), blurRadius: 8)]
              : null,
        ),
        // Inset 2px ring just inside the outer border: the "bevel" look.
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: ArmorUpColors.cardInnerStroke, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
                  child: SizedBox(
                    height: 54,
                    child: _IllustrationBox(spec: spec),
                  ),
                ),
                Container(
                  color: banner,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      def.name,
                      maxLines: 1,
                      style: const TextStyle(
                        color: ArmorUpColors.fontColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        shadows: ArmorUpColors.titleOutline,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: ArmorUpColors.descriptionBackground,
                    padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            describeEffect(def),
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.25,
                              color: ArmorUpColors.fontColor,
                            ),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          def.verseRef,
                          style: TextStyle(
                            fontSize: 9,
                            fontStyle: FontStyle.italic,
                            color: ArmorUpColors.fontColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The illustration area: real art when [CardDisplaySpec.illustrationAssetPath]
/// is set, otherwise the placeholder icon inside a muted dashed frame.
class _IllustrationBox extends StatelessWidget {
  final CardDisplaySpec spec;

  const _IllustrationBox({required this.spec});

  @override
  Widget build(BuildContext context) {
    final assetPath = spec.illustrationAssetPath;
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: ArmorUpColors.cardStroke.withValues(alpha: 0.4),
      ),
      child: assetPath != null
          // Final art will be pixel art: never let default filtering blur
          // it on scale.
          ? Image.asset(
              assetPath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            )
          : Center(
              child: Icon(
                spec.iconPlaceholder,
                size: 30,
                color: ArmorUpColors.cardStroke.withValues(alpha: 0.55),
              ),
            ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(3),
      ));

    const dashLength = 4.0;
    const gapLength = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashLength),
          paint,
        );
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
