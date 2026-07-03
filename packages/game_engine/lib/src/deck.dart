import 'models/armor.dart';
import 'models/card.dart';

/// Single source of truth for every card in the standard Armor Up! deck.
/// Keep this list diffable against the external print-and-play card list:
/// one row per card definition, in the same grouping (attack / defense /
/// restore / event) as the design spec.
const List<CardDef> deckDefinitions = [
  // --- Attack cards (Trials) ---
  CardDef(
    id: 'doubt',
    name: 'Doubt',
    type: CardType.attack,
    targetRule: TargetRule.specificArmorOnPlayer,
    effect: EffectPrimitive.weakenOrHit,
    fixedTarget: ArmorType.shield,
    verseRef: 'Matt 14:31',
    countInDeck: 4,
  ),
  CardDef(
    id: 'deception',
    name: 'Deception',
    type: CardType.attack,
    targetRule: TargetRule.specificArmorOnPlayer,
    effect: EffectPrimitive.weakenOrHit,
    fixedTarget: ArmorType.belt,
    verseRef: 'Eph 4:14',
    countInDeck: 4,
  ),
  CardDef(
    id: 'pride',
    name: 'Pride',
    type: CardType.attack,
    targetRule: TargetRule.specificArmorOnPlayer,
    effect: EffectPrimitive.weakenOrHit,
    fixedTarget: ArmorType.breastplate,
    verseRef: 'Prov 16:18',
    countInDeck: 4,
  ),
  CardDef(
    id: 'discouragement',
    name: 'Discouragement',
    type: CardType.attack,
    targetRule: TargetRule.specificArmorOnPlayer,
    effect: EffectPrimitive.weakenOrHit,
    fixedTarget: ArmorType.helmet,
    verseRef: 'Josh 1:9',
    countInDeck: 4,
  ),
  CardDef(
    id: 'strife',
    name: 'Strife',
    type: CardType.attack,
    targetRule: TargetRule.specificArmorOnPlayer,
    effect: EffectPrimitive.weakenOrHit,
    fixedTarget: ArmorType.shoes,
    verseRef: 'Prov 17:14',
    countInDeck: 4,
  ),
  CardDef(
    id: 'confusion',
    name: 'Confusion',
    type: CardType.attack,
    targetRule: TargetRule.specificArmorOnPlayer,
    effect: EffectPrimitive.weakenOrHit,
    fixedTarget: ArmorType.sword,
    verseRef: '1 Cor 14:33',
    countInDeck: 4,
  ),
  CardDef(
    id: 'fiery_dart',
    name: 'Fiery Dart',
    type: CardType.attack,
    targetRule: TargetRule.anyPieceOnPlayer,
    effect: EffectPrimitive.weakenOrHit,
    verseRef: 'Eph 6:16',
    countInDeck: 6,
  ),
  CardDef(
    id: 'goliaths_taunt',
    name: "Goliath's Taunt",
    type: CardType.attack,
    targetRule: TargetRule.anyPieceOnPlayer,
    effect: EffectPrimitive.doubleHit,
    verseRef: '1 Sam 17',
    countInDeck: 2,
  ),

  // --- Defense cards ---
  CardDef(
    id: 'prayer',
    name: 'Prayer',
    type: CardType.defense,
    targetRule: TargetRule.none,
    effect: EffectPrimitive.blockAttack,
    verseRef: 'Phil 4:6',
    countInDeck: 6,
  ),
  CardDef(
    id: 'it_is_written',
    name: 'It Is Written',
    type: CardType.defense,
    targetRule: TargetRule.none,
    effect: EffectPrimitive.reflectAttack,
    verseRef: 'Matt 4:4',
    countInDeck: 3,
  ),
  CardDef(
    id: 'fellowship',
    name: 'Fellowship',
    type: CardType.defense,
    targetRule: TargetRule.none,
    effect: EffectPrimitive.fellowshipRequest,
    verseRef: 'Ecc 4:12',
    countInDeck: 3,
  ),

  // --- Restore cards ---
  CardDef(
    id: 'fasting',
    name: 'Fasting',
    type: CardType.restore,
    targetRule: TargetRule.ownArmorPiece,
    effect: EffectPrimitive.skipNextTurnAndRestore,
    verseRef: 'Matt 6:17',
    countInDeck: 3,
  ),
  CardDef(
    id: 'renewal',
    name: 'Renewal',
    type: CardType.restore,
    targetRule: TargetRule.ownArmorPiece,
    effect: EffectPrimitive.restoreOneStep,
    verseRef: 'Rom 12:2',
    countInDeck: 5,
  ),
  CardDef(
    id: 'armor_bearer',
    name: 'Armor Bearer',
    type: CardType.restore,
    targetRule: TargetRule.ownArmorPiece,
    effect: EffectPrimitive.restoreFullyFromLost,
    verseRef: '1 Sam 14:7',
    countInDeck: 3,
  ),

  // --- Event cards ---
  CardDef(
    id: 'jericho_march',
    name: 'Jericho March',
    type: CardType.event,
    targetRule: TargetRule.allPlayers,
    effect: EffectPrimitive.allWeakenedToLost,
    verseRef: 'Josh 6',
    countInDeck: 1,
  ),
  CardDef(
    id: 'wilderness_season',
    name: 'Wilderness Season',
    type: CardType.event,
    targetRule: TargetRule.allPlayers,
    effect: EffectPrimitive.allDiscardOne,
    verseRef: 'Deut 8:2',
    countInDeck: 2,
  ),
  CardDef(
    id: 'road_to_damascus',
    name: 'Road to Damascus',
    type: CardType.event,
    targetRule: TargetRule.singlePlayer,
    effect: EffectPrimitive.stealRandomCard,
    verseRef: 'Acts 9',
    countInDeck: 2,
  ),
];

final Map<String, CardDef> _defsById = {
  for (final def in deckDefinitions) def.id: def,
};

/// Looks up a [CardDef] by id. Throws [ArgumentError] if unknown, since an
/// unknown id can only mean an engine bug, not a game-rule violation.
CardDef cardDefById(String id) {
  final def = _defsById[id];
  if (def == null) {
    throw ArgumentError.value(id, 'id', 'No CardDef with this id');
  }
  return def;
}

/// Total number of cards in a standard deck (should be 62).
int get standardDeckSize =>
    deckDefinitions.fold(0, (sum, def) => sum + def.countInDeck);
