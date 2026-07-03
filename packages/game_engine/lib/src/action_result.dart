import 'models/game_state.dart';

/// Outcome of [applyAction]. Game-rule violations (wrong turn, card not in
/// hand, invalid target, etc.) always produce [ActionFailure] rather than
/// throwing; exceptions are reserved for programmer errors (unknown card
/// ids, malformed state).
sealed class ActionResult {
  const ActionResult();
}

final class ActionSuccess extends ActionResult {
  final GameState state;

  const ActionSuccess(this.state);
}

final class ActionFailure extends ActionResult {
  final String reason;

  const ActionFailure(this.reason);

  @override
  String toString() => 'ActionFailure($reason)';
}
