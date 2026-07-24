/// A player's chosen avatar look, as ARGB color ints so this package (pure
/// Dart, no Flutter dependency) doesn't need `dart:ui`'s `Color`. The app
/// layer's `AvatarPalette`/`Character` (see `lib/state/character_controller.dart`
/// and `lib/widgets/pixel_ui.dart`) converts to/from this at the edges.
final class LobbyAvatar {
  final int hair;
  final int skin;
  final int eye;
  final int accent;
  final bool female;

  const LobbyAvatar({
    required this.hair,
    required this.skin,
    required this.eye,
    required this.accent,
    required this.female,
  });

  Map<String, dynamic> toJson() => {
        'hair': hair,
        'skin': skin,
        'eye': eye,
        'accent': accent,
        'female': female,
      };

  static LobbyAvatar fromJson(Map<String, dynamic> json) => LobbyAvatar(
        hair: json['hair'] as int,
        skin: json['skin'] as int,
        eye: json['eye'] as int,
        accent: json['accent'] as int,
        female: json['female'] as bool,
      );
}

/// One player's entry in the pre-game lobby roster, as seen by everyone
/// (including the player themselves). [playerId] is minted by the host at
/// join time, in join order - `newGame` (see `packages/game_engine`)
/// assigns `'p0'`, `'p1'`, ... in list order, so the roster's join order
/// becomes the engine's player order once the host starts the game.
/// [avatar] is null for a player who hasn't customized one (falls back to
/// the seed-derived look everywhere it's rendered).
final class LobbyPlayer {
  final String playerId;
  final String displayName;
  final LobbyAvatar? avatar;

  const LobbyPlayer({required this.playerId, required this.displayName, this.avatar});

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'displayName': displayName,
        if (avatar != null) 'avatar': avatar!.toJson(),
      };

  static LobbyPlayer fromJson(Map<String, dynamic> json) => LobbyPlayer(
        playerId: json['playerId'] as String,
        displayName: json['displayName'] as String,
        avatar: json['avatar'] != null
            ? LobbyAvatar.fromJson(json['avatar'] as Map<String, dynamic>)
            : null,
      );

  @override
  String toString() => 'LobbyPlayer($playerId, $displayName)';
}
