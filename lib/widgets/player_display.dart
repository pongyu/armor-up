import 'package:flutter/material.dart';

import '../theme/armor_up_colors.dart';

/// Display-only metadata for one player's portrait: the placeholder icon
/// shown until real art exists, and the (nullable) asset path of the final
/// art. Mirrors [CardDisplaySpec] in `card_display.dart`.
///
/// Keyed by [PlayerState.id] rather than name: player names are freeform
/// text entered at setup, so they aren't a stable key the way a card's
/// fixed def id is. There is no per-player registry yet - everyone falls
/// back to the same placeholder until real portraits are wired up, at
/// which point per-id entries can be added the same way `cardDisplaySpecs`
/// keys per-card art.
class PlayerDisplaySpec {
  final IconData iconPlaceholder;
  final String? portraitAssetPath;

  const PlayerDisplaySpec({
    this.iconPlaceholder = Icons.person,
    this.portraitAssetPath,
  });
}

const _fallbackPlayerSpec = PlayerDisplaySpec();

PlayerDisplaySpec displaySpecForPlayer(String playerId) => _fallbackPlayerSpec;

/// A player's portrait: real art when [PlayerDisplaySpec.portraitAssetPath]
/// is set, otherwise a placeholder icon in a warm parchment frame.
class PlayerPortrait extends StatelessWidget {
  final String playerId;
  final double size;

  const PlayerPortrait({super.key, required this.playerId, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final spec = displaySpecForPlayer(playerId);
    final assetPath = spec.portraitAssetPath;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ArmorUpColors.cardBackground,
        shape: BoxShape.circle,
        border: Border.all(color: ArmorUpColors.cardStroke, width: 3),
      ),
      child: ClipOval(
        child: assetPath != null
            ? Image.asset(
                assetPath,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none,
              )
            : Icon(
                spec.iconPlaceholder,
                size: size * 0.55,
                color: ArmorUpColors.cardStroke.withValues(alpha: 0.55),
              ),
      ),
    );
  }
}
