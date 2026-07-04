/// A table-wide discard obligation created by an event card (currently
/// only Wilderness Season): every player in [owedPlayerIds] must discard
/// exactly one card of their choice before normal play resumes.
///
/// Modeled as explicit engine state (not a UI dialog), the same way
/// [PendingInterrupt] tracks a pending attack, so a future network layer
/// can drive the same multi-player prompt sequence across clients: while
/// [GameState.pendingGroupDiscard] is non-null, `applyAction` only accepts
/// [DiscardCard] from a player still listed in [owedPlayerIds].
final class PendingGroupDiscard {
  /// Ids of players who still owe a discard. Players are removed one at a
  /// time as they discard; once empty, the pending state is cleared
  /// entirely (set to null) rather than left around as an empty set, so
  /// `pendingGroupDiscard != null` alone is always a reliable "is this
  /// active" check.
  final Set<String> owedPlayerIds;

  const PendingGroupDiscard({required this.owedPlayerIds});

  PendingGroupDiscard copyWith({Set<String>? owedPlayerIds}) =>
      PendingGroupDiscard(owedPlayerIds: owedPlayerIds ?? this.owedPlayerIds);

  @override
  String toString() => 'PendingGroupDiscard($owedPlayerIds)';
}
