import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

Color colorForCardType(CardType type) => switch (type) {
      CardType.attack => Colors.red.shade400,
      CardType.defense => Colors.blue.shade400,
      CardType.restore => Colors.green.shade500,
      CardType.event => Colors.purple.shade400,
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

/// A single card, rendered as a flat colored placeholder (no artwork yet):
/// name, type, effect text, and verse reference.
class CardWidget extends StatelessWidget {
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
    final color = colorForCardType(def.type);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 130,
        height: 170,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.6),
            width: selected ? 3 : 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                labelForCardType(def.type),
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              def.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                describeEffect(def),
                style: const TextStyle(fontSize: 11),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              def.verseRef,
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
