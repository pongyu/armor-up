import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';

import 'filtered_state_adapter.dart';
import 'game_controller.dart';

/// Owns a [GameClient] for networked play and mirrors [GameController]'s
/// public shape (dispatch a [GameAction], expose [GameUiState]) so
/// `gameStateProvider`/`gameErrorProvider` and every widget built against
/// them work unmodified in LAN mode. Never calls `applyAction` locally -
/// every action goes to the host, and [state] is only ever updated by
/// reconstructing whatever [FilteredGameState] the host last sent (see
/// [reconstructFromFiltered]).
///
/// This does not create the [GameClient] itself - the client is created
/// and taken through the lobby phase (connect/host, join lobby, wait for
/// [GameClient.lobbyStarted]) by the lobby screens, then handed to
/// [NetGameController.attach] once actual gameplay begins.
class NetGameController extends StateNotifier<GameUiState?> implements GameActionDispatcher {
  GameClient? _client;
  StreamSubscription<FilteredGameState>? _statesSub;
  StreamSubscription<String>? _errorsSub;

  NetGameController() : super(null);

  /// Starts driving UI state from [client]'s in-game streams. Call once,
  /// right after [GameClient.lobbyStarted] fires (i.e. once
  /// [GameClient.playerId] is set and the host has begun sending
  /// [FilteredGameState]).
  void attach(GameClient client) {
    _client = client;
    _statesSub = client.states.listen((filtered) {
      state = GameUiState(state: reconstructFromFiltered(filtered), lastError: null);
    });
    _errorsSub = client.errors.listen((reason) {
      final current = state;
      if (current != null) {
        state = current.copyWith(lastError: reason);
      }
    });
  }

  /// This device's own engine player id, i.e. whose hand/board this
  /// device should render. Null before [attach]. Unlike hotseat - where
  /// the board follows whoever's turn it is - a LAN device always shows
  /// its own player, so screens read this rather than `currentActorId`.
  String? get localPlayerId => _client?.playerId;

  /// Sends [action] to the host. This class never validates it locally -
  /// the host's next state push (or an error on [GameClient.errors]) is
  /// the only source of truth.
  @override
  bool dispatch(GameAction action) {
    if (_client == null) return false;
    _client!.dispatch(action);
    return true;
  }

  @override
  void clearError() {
    final current = state;
    if (current != null) {
      state = current.copyWith(clearError: true);
    }
  }

  /// Detaches from the current client's streams and clears displayed
  /// state, without closing the client itself - callers that own the
  /// [GameClient] lifecycle (e.g. on host-disconnected) are responsible
  /// for calling [GameClient.close] separately.
  void reset() {
    _statesSub?.cancel();
    _errorsSub?.cancel();
    _statesSub = null;
    _errorsSub = null;
    _client = null;
    state = null;
  }

  @override
  void dispose() {
    _statesSub?.cancel();
    _errorsSub?.cancel();
    super.dispose();
  }
}

final netGameControllerProvider =
    StateNotifierProvider<NetGameController, GameUiState?>((ref) => NetGameController());
