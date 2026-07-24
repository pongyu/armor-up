import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';

/// Wraps the pure-Dart [GameState] plus the most recent [ActionFailure]
/// reason (if any), so the UI can show a transient error without the
/// engine itself knowing about UI concerns.
class GameUiState {
  final GameState state;
  final String? lastError;

  /// Mirrors [StateMessage.responseDeadlineEpochMs] in LAN mode - the
  /// epoch-millisecond instant the host's defense-response/group-discard
  /// timeout will fire for the current pending actor, or null if none is
  /// running. Always null in hotseat, where [GameController] has no host
  /// or timer concept at all and never sets this field.
  final int? responseDeadlineEpochMs;

  /// Mirrors [FilteredGameState.connectedPlayerIds] in LAN mode - engine
  /// player ids whose socket the host currently considers live, so the UI
  /// can show a seat as "reconnecting..." instead of leaving a stalled
  /// turn unexplained. Always empty in hotseat, where every "player" is
  /// the same device and there is no connection concept - callers should
  /// treat an empty set as "connection status unknown/not applicable",
  /// not "everyone disconnected".
  final Set<String> connectedPlayerIds;

  const GameUiState({
    required this.state,
    this.lastError,
    this.responseDeadlineEpochMs,
    this.connectedPlayerIds = const {},
  });

  GameUiState copyWith({
    GameState? state,
    String? lastError,
    bool clearError = false,
    int? responseDeadlineEpochMs,
    bool clearResponseDeadline = false,
    Set<String>? connectedPlayerIds,
  }) =>
      GameUiState(
        state: state ?? this.state,
        lastError: clearError ? null : (lastError ?? this.lastError),
        responseDeadlineEpochMs: clearResponseDeadline
            ? null
            : (responseDeadlineEpochMs ?? this.responseDeadlineEpochMs),
        connectedPlayerIds: connectedPlayerIds ?? this.connectedPlayerIds,
      );
}

/// Common shape shared by [GameController] (hotseat, local `applyAction`)
/// and `NetGameController` (LAN, dispatches over a `GameClient`), so
/// screens can send input through whichever one is currently active
/// (`activeGameControllerProvider` in `app_mode_controller.dart`) without
/// knowing which mode they're in.
abstract class GameActionDispatcher {
  bool dispatch(GameAction action);
  void clearError();
}

/// Owns the single [GameState] for the current hotseat game and is the
/// only place in the Flutter app that calls [applyAction]. Every user
/// input in the UI becomes a [GameAction] passed to [dispatch], mirroring
/// exactly how a future networked client would drive the same engine.
class GameController extends StateNotifier<GameUiState?> implements GameActionDispatcher {
  GameController() : super(null);

  void startGame({
    required List<String> playerNames,
    int? seed,
    bool restorationWinEnabled = true,
  }) {
    final game = newGame(
      playerNames: playerNames,
      seed: seed ?? DateTime.now().millisecondsSinceEpoch,
      restorationWinEnabled: restorationWinEnabled,
    );
    state = GameUiState(state: game);
  }

  /// Applies [action]. Returns true if it succeeded. On failure, the
  /// reason is stored in [GameUiState.lastError] for the UI to display,
  /// and the game state itself is left unchanged.
  @override
  bool dispatch(GameAction action) {
    final current = state;
    if (current == null) return false;

    final result = applyAction(current.state, action);
    switch (result) {
      case ActionSuccess(state: final newState):
        state = current.copyWith(state: newState, clearError: true);
        return true;
      case ActionFailure(:final reason):
        state = current.copyWith(lastError: reason);
        return false;
    }
  }

  @override
  void clearError() {
    final current = state;
    if (current != null) {
      state = current.copyWith(clearError: true);
    }
  }

  void endGame() {
    state = null;
  }
}

final gameControllerProvider = StateNotifierProvider<GameController, GameUiState?>(
  (ref) => GameController(),
);
