import 'armor.dart';

/// The four card categories in Armor Up!.
enum CardType { attack, defense, restore, event }

/// How a card selects its target(s) when played. Interpreted by the engine
/// alongside [EffectSpec] to resolve a [PlayCard] action without per-card
/// logic branches.
enum TargetRule {
  /// Targets a single, fixed armor type across an opposing player (e.g.
  /// Doubt always targets a Shield of Faith). The opposing player must
  /// still be chosen; the armor type is implied by [CardDef.fixedTarget].
  specificArmorOnPlayer,

  /// Targets any single armor piece (attacker's choice) on a chosen
  /// opposing player.
  anyPieceOnPlayer,

  /// Targets a single opposing player as a whole, no armor piece choice
  /// (e.g. Road to Damascus steals a random card).
  singlePlayer,

  /// Affects all other players / the whole table with no target selection.
  allPlayers,

  /// Targets one of the acting player's own armor pieces.
  ownArmorPiece,

  /// No target at all (e.g. Fasting's skip-turn half, Fellowship's request
  /// to the table).
  none,
}

/// Closed set of effect primitives. Every [CardDef] maps to exactly one of
/// these; new cards become new data rows in the deck table rather than new
/// engine branches, unless they truly need a new primitive.
enum EffectPrimitive {
  /// Weaken a Strong piece, or destroy (Lost) a Weakened piece.
  weakenOrHit,

  /// Two hits in one resolution: Strong -> Lost directly.
  doubleHit,

  /// Block the pending attack entirely; it has no effect.
  blockAttack,

  /// Block the pending attack and re-throw it back at its attacker as a
  /// new pending attack with the same target rule/strength.
  reflectAttack,

  /// Ask the table for help; if any other player discards a defense card,
  /// the attack is blocked. Otherwise the original defender may still
  /// respond with their own defense card.
  fellowshipRequest,

  /// Weakened -> Strong on one of the acting player's own pieces.
  restoreOneStep,

  /// Lost -> Strong on one of the acting player's own pieces.
  restoreFullyFromLost,

  /// Skip the acting player's next play step (they still draw), and fully
  /// restore one of their own pieces (any condition) to Strong as part of
  /// playing this card.
  skipNextTurnAndRestore,

  /// Every player's Weakened pieces become Lost.
  allWeakenedToLost,

  /// Every player discards one card of their choice.
  allDiscardOne,

  /// Steal a random card from a chosen opposing player's hand.
  stealRandomCard,
}

/// Static rules-data for one card. Definitions live only in [deckDefinitions]
/// (see `deck.dart`) so the card list has a single source of truth that can
/// be diffed against an external print-and-play spec.
final class CardDef {
  /// Stable identifier, e.g. `'doubt'`, `'fiery_dart'`. Never shown to
  /// players; used for lookups and event logging.
  final String id;
  final String name;
  final CardType type;
  final TargetRule targetRule;
  final EffectPrimitive effect;

  /// Set only for [TargetRule.specificArmorOnPlayer] cards.
  final ArmorType? fixedTarget;

  /// Display-only scripture reference, e.g. `'Eph 6:16'`.
  final String verseRef;

  /// Display-only flavor text. Empty until supplied separately.
  final String flavorText;

  /// How many copies of this card are in the standard deck.
  final int countInDeck;

  const CardDef({
    required this.id,
    required this.name,
    required this.type,
    required this.targetRule,
    required this.effect,
    this.fixedTarget,
    required this.verseRef,
    this.flavorText = '',
    required this.countInDeck,
  });

  @override
  String toString() => 'CardDef($id)';
}

/// A concrete, distinguishable card occurrence in a deck/hand/discard pile.
/// Two copies of the same [CardDef] in a hand are different [CardInstance]s
/// with different [instanceId]s.
final class CardInstance {
  final String instanceId;
  final String defId;

  const CardInstance({required this.instanceId, required this.defId});

  @override
  bool operator ==(Object other) =>
      other is CardInstance && other.instanceId == instanceId;

  @override
  int get hashCode => instanceId.hashCode;

  @override
  String toString() => 'CardInstance($instanceId:$defId)';
}
