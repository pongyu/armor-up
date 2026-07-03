/// How a game was won, so the UI can show a different win screen for each.
enum WinType {
  /// All other players have lost all six armor pieces.
  elimination,

  /// The winner had all six armor pieces at Strong simultaneously at the
  /// start of their turn.
  restoration,
}

final class WinResult {
  final String winnerId;
  final WinType type;

  const WinResult({required this.winnerId, required this.type});

  @override
  bool operator ==(Object other) =>
      other is WinResult && other.winnerId == winnerId && other.type == type;

  @override
  int get hashCode => Object.hash(winnerId, type);

  @override
  String toString() => 'WinResult($winnerId, ${type.name})';
}
