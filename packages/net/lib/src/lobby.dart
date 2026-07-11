/// One player's entry in the pre-game lobby roster, as seen by everyone
/// (including the player themselves). [playerId] is minted by the host at
/// join time, in join order - `newGame` (see `packages/game_engine`)
/// assigns `'p0'`, `'p1'`, ... in list order, so the roster's join order
/// becomes the engine's player order once the host starts the game.
final class LobbyPlayer {
  final String playerId;
  final String displayName;

  const LobbyPlayer({required this.playerId, required this.displayName});

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'displayName': displayName,
      };

  static LobbyPlayer fromJson(Map<String, dynamic> json) => LobbyPlayer(
        playerId: json['playerId'] as String,
        displayName: json['displayName'] as String,
      );

  @override
  String toString() => 'LobbyPlayer($playerId, $displayName)';
}
