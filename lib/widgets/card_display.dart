import 'package:flutter/material.dart';

/// Display-only metadata for one card: the placeholder icon shown until
/// real artwork exists, and the (nullable) asset path of the final art.
///
/// Swapping in real art is a one-line change per card: add
/// `illustrationAssetPath: 'assets/cards/<id>.png'` to its entry below.
/// [CardWidget] renders the asset when the path is set and falls back to
/// the placeholder icon otherwise.
class CardDisplaySpec {
  final IconData iconPlaceholder;
  final String? illustrationAssetPath;

  const CardDisplaySpec(this.iconPlaceholder, {this.illustrationAssetPath});
}

/// Keyed by [CardDef.id]. Icons are explicitly placeholders, not final
/// art - keep them simple.
const cardDisplaySpecs = <String, CardDisplaySpec>{
  // Attacks (Trials).
  'doubt': CardDisplaySpec(
    Icons.help_outline,
    illustrationAssetPath: 'assets/cards/doubt.png',
  ),
  'deception': CardDisplaySpec(
    Icons.visibility_off,
    illustrationAssetPath: 'assets/cards/deception.png',
  ),
  'pride': CardDisplaySpec(
    Icons.workspace_premium,
    illustrationAssetPath: 'assets/cards/pride.png',
  ),
  'discouragement': CardDisplaySpec(
    Icons.cloud,
    illustrationAssetPath: 'assets/cards/discouragement.png',
  ),
  'strife': CardDisplaySpec(
    Icons.sports_kabaddi,
    illustrationAssetPath: 'assets/cards/strife.png',
  ),
  'confusion': CardDisplaySpec(
    Icons.shuffle,
    illustrationAssetPath: 'assets/cards/confusion.png',
  ),
  'fiery_dart': CardDisplaySpec(
    Icons.local_fire_department,
    illustrationAssetPath: 'assets/cards/fiery_dart.png',
  ),
  'goliaths_taunt': CardDisplaySpec(
    Icons.campaign,
    illustrationAssetPath: 'assets/cards/goliaths_taunt.png',
  ),
  // Defenses.
  'prayer': CardDisplaySpec(
    Icons.front_hand,
    illustrationAssetPath: 'assets/cards/prayer.png',
  ),
  'it_is_written': CardDisplaySpec(
    Icons.menu_book,
    illustrationAssetPath: 'assets/cards/it_is_written.png',
  ),
  'fellowship': CardDisplaySpec(
    Icons.groups,
    illustrationAssetPath: 'assets/cards/fellowship.png',
  ),
  // Restores.
  'fasting': CardDisplaySpec(
    Icons.hourglass_empty,
    illustrationAssetPath: 'assets/cards/fasting.png',
  ),
  'renewal': CardDisplaySpec(
    Icons.eco,
    illustrationAssetPath: 'assets/cards/renewal.png',
  ),
  'armor_bearer': CardDisplaySpec(
    Icons.shield,
    illustrationAssetPath: 'assets/cards/armor_bearer.png',
  ),
  // Events.
  'jericho_march': CardDisplaySpec(
    Icons.castle,
    illustrationAssetPath: 'assets/cards/jericho_march.png',
  ),
  'wilderness_season': CardDisplaySpec(
    Icons.terrain,
    illustrationAssetPath: 'assets/cards/wilderness_season.png',
  ),
  'road_to_damascus': CardDisplaySpec(
    Icons.wb_sunny,
    illustrationAssetPath: 'assets/cards/road_to_damascus.png',
  ),
};

const _fallbackSpec = CardDisplaySpec(Icons.style);

CardDisplaySpec displaySpecFor(String defId) =>
    cardDisplaySpecs[defId] ?? _fallbackSpec;
