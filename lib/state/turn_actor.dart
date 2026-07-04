import 'package:game_engine/game_engine.dart';

/// Determines whose hand/decision the UI should currently be showing.
/// During normal play this is the active player; during a defense
/// interrupt it is the defender (or, while a Fellowship request is open,
/// any player who has not yet declined); during a group discard (e.g.
/// Wilderness Season) it is one of the players who still owes a discard.
///
/// This only reports who needs to act next - it does not decide whether
/// a "pass the phone" screen should be shown first; that is purely a UI
/// concern layered on top (see [PassGate] usage in the game screen), since
/// the engine has no notion of device-passing.
String currentActorId(GameState state) {
  final groupDiscard = state.pendingGroupDiscard;
  if (groupDiscard != null) {
    return groupDiscard.owedPlayerIds.first;
  }

  final pending = state.pendingInterrupt;
  if (pending == null) {
    return state.activePlayer.id;
  }

  if (pending.fellowshipRequested) {
    final undecided = state.players.where(
      (p) =>
          p.id != pending.defenderId &&
          p.id != pending.attackerId &&
          !p.isEliminated &&
          !pending.helpersDeclined.contains(p.id),
    );
    if (undecided.isNotEmpty) return undecided.first.id;
  }

  return pending.defenderId;
}
