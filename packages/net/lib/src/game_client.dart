import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:game_engine/game_engine.dart';

import 'filtered_state.dart';
import 'lobby.dart';
import 'messages.dart';

/// Connects to a [HostServer], first through its pre-game lobby and then,
/// once the host starts the game, as a specific engine player. Never runs
/// [applyAction] locally - every action is sent to the host and this class
/// only ever displays whatever [FilteredGameState] the host sends back.
/// This mirrors [GameController.dispatch] in the app's Riverpod layer, but
/// over the wire instead of in-process.
///
/// Lifecycle: [connectToLobby] -> [lobbyRoster] updates as players join ->
/// [lobbyStarted] fires once (with [playerId] now set) -> [states]/[errors]
/// flow as normal. If the connection drops mid-game, [reconnect] presents
/// the same [playerId] and the token captured from [lobbyStarted] to
/// reclaim the seat.
class GameClient {
  String? _playerId;
  String? _sessionToken;
  String? _hostAddress;
  int? _hostPort;
  WebSocket? _socket;
  bool _closing = false;
  bool _endedDeliberately = false;
  List<LobbyPlayer> _latestRoster = const [];
  FilteredGameState? _latestState;
  int? _latestResponseDeadlineEpochMs;

  final _lobbyRosterController = StreamController<List<LobbyPlayer>>.broadcast();
  final _lobbyStartedController = StreamController<void>.broadcast();
  final _lobbyStartedCompleter = Completer<void>();
  final _joinRejectedController = StreamController<String>.broadcast();
  final _stateController = StreamController<FilteredGameState>.broadcast();
  final _responseDeadlineController = StreamController<int?>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _hostDisconnectedController = StreamController<void>.broadcast();
  final _playerLeftController = StreamController<String>.broadcast();
  final _connectionLostController = StreamController<void>.broadcast();

  /// This client's engine player id, assigned by the host once the game
  /// starts (see [lobbyStarted]); null during the lobby phase.
  String? get playerId => _playerId;

  /// The host address/port last connected to via [connectToLobby] or
  /// [reconnect], for a caller that wants to persist enough to retry a
  /// later [reconnect] without the user re-entering them (e.g. across an
  /// app restart). Null before the first successful connect.
  String? get hostAddress => _hostAddress;
  int? get hostPort => _hostPort;

  /// The lobby roster, updated every time it changes while in the lobby
  /// phase (including immediately after [connectToLobby]/[reconnect]).
  /// Since this is a broadcast stream, a listener that subscribes after
  /// the first broadcast has already gone out (a real risk - UI code
  /// typically subscribes in `initState`, after `await connectToLobby`
  /// has already returned) would otherwise miss it entirely; use
  /// [latestRoster] to seed initial UI state instead of assuming the
  /// stream's first event is still coming.
  Stream<List<LobbyPlayer>> get lobbyRoster => _lobbyRosterController.stream;

  /// The most recently received lobby roster, synchronously available -
  /// see [lobbyRoster] for why this matters. Empty before the first
  /// [LobbyRosterMessage] arrives.
  List<LobbyPlayer> get latestRoster => _latestRoster;

  /// Fires once, when the host starts the game. [playerId] is set by the
  /// time this fires. Prefer [whenStarted] in UI code: this is a broadcast
  /// stream, so a listener attached after the host has already started
  /// (a real race - the host can start in the window between connecting
  /// and subscribing) would miss the event entirely and wait forever.
  Stream<void> get lobbyStarted => _lobbyStartedController.stream;

  /// Completes when the host starts the game, and completes immediately if
  /// it already has. Timing-safe replacement for `lobbyStarted.first` -
  /// awaiting this never hangs just because the subscription came a beat
  /// too late.
  Future<void> get whenStarted => _lobbyStartedCompleter.future;

  /// Whether the host has already started the game.
  bool get hasStarted => _lobbyStartedCompleter.isCompleted;

  /// Fires if a join or reconnect attempt is refused (lobby full, name
  /// taken, invalid/expired reconnect token, ...).
  Stream<String> get joinRejected => _joinRejectedController.stream;

  /// The latest player-filtered state pushed by the host.
  Stream<FilteredGameState> get states => _stateController.stream;

  /// The most recently received state, synchronously available. Since
  /// [states] is a broadcast stream with no replay, the host's first
  /// [StateMessage] - sent as part of the same [HostServer.startGame] call
  /// that completes [whenStarted] - can arrive and be missed before UI code
  /// reacting to [whenStarted] gets a chance to subscribe. Callers should
  /// seed initial UI state from this rather than assuming the stream's
  /// first event is still coming. Null before the first [StateMessage]
  /// arrives.
  FilteredGameState? get latestState => _latestState;

  /// The response-deadline envelope field from the most recent
  /// [StateMessage] - see that class's doc comment for what it means.
  /// Broadcast alongside (not folded into) [states], since it changes
  /// independently of [FilteredGameState] content (e.g. ticking toward
  /// its instant needs no state change to justify a UI rebuild) and a
  /// widget only interested in the countdown shouldn't need to rebuild on
  /// every unrelated state broadcast to get it.
  Stream<int?> get responseDeadlines => _responseDeadlineController.stream;

  /// The most recently received deadline, synchronously available - same
  /// "seed from this, don't assume the stream's first event is still
  /// coming" rationale as [latestState]. Null before the first
  /// [StateMessage] arrives, or whenever no deadline is currently running.
  int? get latestResponseDeadlineEpochMs => _latestResponseDeadlineEpochMs;

  /// One-shot [ActionFailure] reasons for actions this client sent.
  Stream<String> get errors => _errorController.stream;

  /// Fires once, when the host deliberately ends the session
  /// ([HostDisconnectedMessage] received) - unrecoverable, unlike
  /// [connectionLost].
  Stream<void> get hostDisconnected => _hostDisconnectedController.stream;

  /// Fires with the departed player's id when their reconnect grace period
  /// expires mid-game, ending the session for everyone. Unrecoverable, same
  /// as [hostDisconnected] - the engine has no concept of continuing
  /// without a seat that never came back.
  Stream<String> get playerLeft => _playerLeftController.stream;

  /// Fires when this client's own socket drops (network blip, host
  /// unreachable, app backgrounded, ...) without the host having sent
  /// [HostDisconnectedMessage] or [PlayerLeftMessage] first - i.e. the
  /// host may well still be running and the seat may still be held during
  /// its reconnect grace period. Distinct from [hostDisconnected]/
  /// [playerLeft] specifically so the UI can offer a retry via [reconnect]
  /// instead of treating every drop as the end of the session.
  Stream<void> get connectionLost => _connectionLostController.stream;

  /// Connects to the host's lobby at [hostAddress]:[port] as a fresh
  /// player named [displayName] (the fallback room-code path just needs
  /// the host's LAN IP typed in here; mDNS discovery resolves the same
  /// address automatically). [avatar] is this device's chosen avatar look,
  /// if any, forwarded to the host for inclusion in the broadcast roster.
  Future<void> connectToLobby(
    String hostAddress,
    int port,
    String displayName, {
    LobbyAvatar? avatar,
  }) async {
    await _connectSocket(hostAddress, port);
    _send(JoinLobbyMessage(displayName: displayName, avatar: avatar));
  }

  /// Reconnects to the host at [hostAddress]:[port], reclaiming the seat
  /// identified by [playerId]/[sessionToken] (captured from a prior
  /// [lobbyStarted], or persisted by the caller across an app restart).
  /// Used both for a mid-lobby reconnect and a mid-game reconnect - safe to
  /// call again on the same [GameClient] after [connectionLost] fires, or
  /// on a freshly constructed one.
  Future<void> reconnect(
    String hostAddress,
    int port,
    String playerId,
    String sessionToken,
  ) async {
    _endedDeliberately = false;
    await _connectSocket(hostAddress, port);
    _playerId = playerId;
    _sessionToken = sessionToken;
    _send(JoinLobbyMessage(rejoinPlayerId: playerId, rejoinToken: sessionToken));
  }

  /// The session token minted for this client once the game starts,
  /// needed to call [reconnect] after a drop. Null until [lobbyStarted]
  /// fires.
  String? get sessionToken => _sessionToken;

  Future<void> _connectSocket(String hostAddress, int port) async {
    final uri = Uri(scheme: 'ws', host: hostAddress, port: port);
    final socket = await WebSocket.connect(uri.toString());
    _socket = socket;
    _hostAddress = hostAddress;
    _hostPort = port;
    _closing = false;
    socket.listen(
      _handleIncoming,
      onDone: _notifySocketClosed,
      onError: (_) => _notifySocketClosed(),
    );
  }

  /// Routes an unexpected socket close to [connectionLost] (recoverable -
  /// [reconnect] may still succeed) unless the host already told us why it
  /// was ending for good ([HostDisconnectedMessage]/[PlayerLeftMessage],
  /// tracked via [_endedDeliberately]) or we initiated the close ourselves
  /// via [close].
  void _notifySocketClosed() {
    if (_closing) return;
    if (_endedDeliberately) return;
    if (!_connectionLostController.isClosed) {
      _connectionLostController.add(null);
    }
  }

  void _handleIncoming(dynamic raw) {
    final NetMessage message;
    try {
      message = NetMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
    } on FormatException {
      return;
    }

    switch (message) {
      case StateMessage(:final state, :final responseDeadlineEpochMs):
        _latestState = state;
        _latestResponseDeadlineEpochMs = responseDeadlineEpochMs;
        if (!_stateController.isClosed) _stateController.add(state);
        if (!_responseDeadlineController.isClosed) {
          _responseDeadlineController.add(responseDeadlineEpochMs);
        }
      case ErrorMessage(:final reason):
        if (!_errorController.isClosed) _errorController.add(reason);
      case HostDisconnectedMessage():
        _endedDeliberately = true;
        if (!_hostDisconnectedController.isClosed) {
          _hostDisconnectedController.add(null);
        }
      case LobbyRosterMessage(:final players):
        _latestRoster = players;
        if (!_lobbyRosterController.isClosed) _lobbyRosterController.add(players);
      case LobbyStartedMessage(:final playerId, :final sessionToken):
        _playerId = playerId;
        _sessionToken = sessionToken;
        if (!_lobbyStartedCompleter.isCompleted) _lobbyStartedCompleter.complete();
        if (!_lobbyStartedController.isClosed) _lobbyStartedController.add(null);
      case JoinRejectedMessage(:final reason):
        if (!_joinRejectedController.isClosed) _joinRejectedController.add(reason);
      case PlayerLeftMessage(:final playerId):
        _endedDeliberately = true;
        if (!_playerLeftController.isClosed) _playerLeftController.add(playerId);
      case ActionMessage():
      case JoinLobbyMessage():
        // Clients never receive these; only send them.
        break;
    }
  }

  /// Sends [action] to the host for validation via `applyAction`. This
  /// class does not know or care whether it succeeds - the host's next
  /// [StateMessage] (or an [ErrorMessage] on [errors]) is the only source
  /// of truth.
  void dispatch(GameAction action) {
    _send(ActionMessage(action));
  }

  void _send(NetMessage message) {
    _socket?.add(jsonEncode(message.toJson()));
  }

  Future<void> close() async {
    _closing = true;
    await _socket?.close();
    await _lobbyRosterController.close();
    await _lobbyStartedController.close();
    await _joinRejectedController.close();
    await _stateController.close();
    await _responseDeadlineController.close();
    await _errorController.close();
    await _hostDisconnectedController.close();
    await _playerLeftController.close();
    await _connectionLostController.close();
  }
}
