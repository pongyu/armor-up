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
  'doubt': CardDisplaySpec(Icons.help_outline),
  'deception': CardDisplaySpec(Icons.visibility_off),
  'pride': CardDisplaySpec(Icons.workspace_premium),
  'discouragement': CardDisplaySpec(Icons.cloud),
  'strife': CardDisplaySpec(Icons.sports_kabaddi),
  'confusion': CardDisplaySpec(Icons.shuffle),
  'fiery_dart': CardDisplaySpec(Icons.local_fire_department),
  'goliaths_taunt': CardDisplaySpec(Icons.campaign),
  // Defenses.
  'prayer': CardDisplaySpec(Icons.front_hand),
  'it_is_written': CardDisplaySpec(Icons.menu_book),
  'fellowship': CardDisplaySpec(Icons.groups),
  // Restores.
  'fasting': CardDisplaySpec(Icons.hourglass_empty),
  'renewal': CardDisplaySpec(Icons.eco),
  'armor_bearer': CardDisplaySpec(Icons.shield),
  // Events.
  'jericho_march': CardDisplaySpec(Icons.castle),
  'wilderness_season': CardDisplaySpec(Icons.terrain),
  'road_to_damascus': CardDisplaySpec(Icons.wb_sunny),
};

const _fallbackSpec = CardDisplaySpec(Icons.style);

CardDisplaySpec displaySpecFor(String defId) =>
    cardDisplaySpecs[defId] ?? _fallbackSpec;
