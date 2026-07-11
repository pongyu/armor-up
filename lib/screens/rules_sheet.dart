import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme/armor_up_colors.dart';

/// Quick-reference "how to play" sheet, opened from the '?' button on the
/// game board's header. Static rules summary, not tied to [GameState] - it
/// answers "what does this mean" at any point in a game, not just for a
/// brand new player, so it stays reachable for the whole match rather than
/// only appearing once via the coach marks in `coach_mark_overlay.dart`.
Future<void> showRulesSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: ArmorUpColors.boardBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => const _RulesSheetContent(),
  );
}

class _RulesSheetContent extends StatelessWidget {
  const _RulesSheetContent();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ArmorUpColors.fontColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'How to play',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: ArmorUpColors.fontColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const _Section(
                title: 'Goal',
                body:
                    'Every player wears six pieces of armor (Ephesians 6). '
                    'You win by being the last player with any armor left, '
                    'by restoring all six pieces to Strong at once, or by '
                    'holding the best armor when the draw pile runs out.',
              ),
              const _Section(
                title: 'Your turn',
                body:
                    '1. Draw a card.\n'
                    '2. Play one card from your hand (optional).\n'
                    '3. Discard down to $maxHandSize cards, then end your turn.',
              ),
              const _Section(
                title: 'Card types',
                body: '',
                child: _CardTypeList(),
              ),
              const _Section(
                title: 'Armor condition',
                body:
                    'Each armor piece is Strong, Weakened, or Lost. An '
                    'attack steps a piece down one level. A Lost piece '
                    'can\'t be attacked again - restore it to bring it '
                    'back into play.',
                child: _ArmorConditionList(),
              ),
              const _Section(
                title: 'Defending',
                body:
                    'When you\'re attacked, play a defense card to block '
                    'or reflect it, or take the hit. Some defense cards '
                    'ask the whole table for help.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  final Widget? child;

  const _Section({required this.title, required this.body, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: ArmorUpColors.goldAccent,
            ),
          ),
          const SizedBox(height: 6),
          if (body.isNotEmpty)
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                color: ArmorUpColors.fontColor,
                height: 1.4,
              ),
            ),
          if (child != null) ...[
            if (body.isNotEmpty) const SizedBox(height: 8),
            child!,
          ],
        ],
      ),
    );
  }
}

class _CardTypeList extends StatelessWidget {
  const _CardTypeList();

  static const _rows = [
    (CardType.attack, ArmorUpColors.bannerAttack, 'Weakens or destroys an opponent\'s armor piece.'),
    (CardType.defense, ArmorUpColors.bannerDefense, 'Blocks, reflects, or asks for help against an attack.'),
    (CardType.restore, ArmorUpColors.bannerRestore, 'Repairs one of your own armor pieces.'),
    (CardType.event, ArmorUpColors.bannerEvent, 'A special one-off effect described on the card.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (type, color, desc) in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 3, right: 8),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: ArmorUpColors.fontColor, height: 1.4),
                      children: [
                        TextSpan(
                          text: '${_typeName(type)}: ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: desc),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _typeName(CardType type) => switch (type) {
    CardType.attack => 'Attack',
    CardType.defense => 'Defense',
    CardType.restore => 'Restore',
    CardType.event => 'Event',
  };
}

class _ArmorConditionList extends StatelessWidget {
  const _ArmorConditionList();

  static const _rows = [
    (ArmorCondition.strong, ArmorUpColors.armorStrong, 'Strong', 'Full protection.'),
    (ArmorCondition.weakened, ArmorUpColors.armorWeakened, 'Weakened', 'One hit taken.'),
    (ArmorCondition.lost, ArmorUpColors.armorLost, 'Lost', 'Two hits taken - can\'t be attacked further.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (_, color, label, desc) in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: ArmorUpColors.cardInnerStroke, width: 1),
                  ),
                ),
                Text(
                  '$label - ',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ArmorUpColors.fontColor,
                  ),
                ),
                Expanded(
                  child: Text(
                    desc,
                    style: const TextStyle(fontSize: 13, color: ArmorUpColors.fontColor, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
