import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:game_engine/game_engine.dart';

import 'filtered_state.dart';
import 'lobby.dart';
import 'messages.dart';

/// One player's host-side bookkeeping: their engine identity, the secret
/// they must present to reclaim this seat, their live socket (null while
/// disconnected mid-game), and - only while disconnected mid-game - the
/// grace-period timer that will fire [HostServer._handlePlayerLeft] if
/// they don't reconnect in time.
class _RosterEntry {
  final String playerId;
  final String displayName;
  final String sessionToken;
  WebSocket? socket;
  Timer? graceTimer;

  _RosterEntry({
    required this.playerId,
    required this.displayName,
    required this.sessionToken,
  });

  bool get isConnected => socket != null;
}

/// A WebSocket's underlying stream can only ever be listened to once, so
/// each connection gets exactly one subscription for its whole lifetime.
/// Routing "first message vs. subsequent messages" (i.e. before vs. after
/// a roster entry exists for this socket) is done by swapping which
/// handlers this mutable holder forwards events to, rather than trying to
/// re-subscribe once the socket is claimed.
class _SocketRoute {
  void Function(dynamic raw) onData;
  void Function() onDone = () {};
  void Function(Object error) onError = (_) {};

  _SocketRoute({required this.onData});
}

/// Minimal LAN host: runs a pre-game lobby, then owns the authoritative
/// [GameState] once started, accepting WebSocket connections on the local
/// network and acting as the only place [applyAction] is called for
/// networked play.
///
/// Lifecycle: construct -> [start] (binds the listening socket, lobby is
/// open) -> players connect and send [JoinLobbyMessage] -> host calls
/// [startGame] once enough players have joined -> [ActionMessage]s flow
/// and [state] becomes non-null.
class HostServer {
  final String hostDisplayName;
  final Random _random;

  HttpServer? _httpServer;
  final List<_RosterEntry> _roster = [];
  GameState? _state;
  bool _gameStarted = false;
  bool _stopped = false;

  /// How long a disconnected player's seat is held before [PlayerLeftMessage]
  /// ends the session. Overridable so tests don't have to wait 60 real
  /// seconds.
  final Duration reconnectGracePeriod;

  HostServer({
    required this.hostDisplayName,
    this.reconnectGracePeriod = const Duration(seconds: 60),
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The authoritative state once [startGame] has been called; null during
  /// the lobby phase.
  GameState? get state => _state;

  /// The current lobby roster (also valid, unchanging in membership, after
  /// the game has started).
  List<LobbyPlayer> get roster => [
        for (final entry in _roster)
          LobbyPlayer(playerId: entry.playerId, displayName: entry.displayName),
      ];

  /// Starts listening on [port] (default 0 = OS-assigned free port) on all
  /// interfaces. Returns the bound port so it can be shown to joiners
  /// (room code / QR code).
  Future<int> start({int port = 0}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _httpServer = server;
    server.listen(_handleHttpRequest);
    return server.port;
  }

  void _handleHttpRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Expected a WebSocket upgrade request')
        ..close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    late final _SocketRoute route;
    route = _SocketRoute(onData: (raw) => _handleFirstMessage(socket, route, raw));
    socket.listen(
      (raw) => route.onData(raw),
      onDone: () => route.onDone(),
      onError: (Object error) => route.onError(error),
    );
  }

  void _handleFirstMessage(WebSocket socket, _SocketRoute route, dynamic raw) {
    final NetMessage message;
    try {
      message = NetMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
    } on FormatException catch (e) {
      socket.add(jsonEncode(JoinRejectedMessage('Malformed message: ${e.message}').toJson()));
      socket.close();
      return;
    }

    if (message is! JoinLobbyMessage) {
      socket.add(jsonEncode(const JoinRejectedMessage('Expected a join message first').toJson()));
      socket.close();
      return;
    }

    if (message.isReconnect) {
      _handleReconnect(socket, route, message.rejoinPlayerId!, message.rejoinToken ?? '');
    } else {
      _handleFreshJoin(socket, route, message.displayName ?? '');
    }
  }

  void _handleFreshJoin(WebSocket socket, _SocketRoute route, String displayName) {
    if (_gameStarted) {
      socket.add(jsonEncode(const JoinRejectedMessage('Game already started').toJson()));
      socket.close();
      return;
    }
    if (_roster.length >= maxPlayers) {
      socket.add(jsonEncode(const JoinRejectedMessage('Lobby is full').toJson()));
      socket.close();
      return;
    }
    if (displayName.trim().isEmpty) {
      socket.add(jsonEncode(const JoinRejectedMessage('A display name is required').toJson()));
      socket.close();
      return;
    }
    if (_roster.any((e) => e.displayName == displayName)) {
      socket.add(jsonEncode(const JoinRejectedMessage('That name is already taken').toJson()));
      socket.close();
      return;
    }

    final entry = _RosterEntry(
      playerId: 'p${_roster.length}',
      displayName: displayName,
      sessionToken: _mintToken(),
    )..socket = socket;
    _roster.add(entry);

    _listenOn(entry, route);
    _broadcastRoster();
  }

  void _handleReconnect(
    WebSocket socket,
    _SocketRoute route,
    String playerId,
    String token,
  ) {
    final entry = _roster.where((e) => e.playerId == playerId).firstOrNull;
    if (entry == null || entry.sessionToken != token) {
      socket.add(jsonEncode(const JoinRejectedMessage('Invalid or expired rejoin token').toJson()));
      socket.close();
      return;
    }
    if (entry.isConnected) {
      socket.add(jsonEncode(const JoinRejectedMessage('That seat is already connected').toJson()));
      socket.close();
      return;
    }

    entry.graceTimer?.cancel();
    entry.graceTimer = null;
    entry.socket = socket;
    _listenOn(entry, route);

    if (_gameStarted) {
      _sendStateTo(entry);
    } else {
      _broadcastRoster();
    }
  }

  void _listenOn(_RosterEntry entry, _SocketRoute route) {
    route.onData = (raw) => _handleIncoming(entry, raw);
    route.onDone = () => _handleDisconnect(entry);
    route.onError = (_) => _handleDisconnect(entry);
  }

  void _handleDisconnect(_RosterEntry entry) {
    entry.socket = null;
    if (!_gameStarted) {
      // No seat to hold before the game exists - dropping out of the
      // lobby just removes them.
      _roster.remove(entry);
      _broadcastRoster();
      return;
    }

    // Mid-game: hold the seat for the grace period rather than ending the
    // session immediately. While disconnected, applyAction's own turn-order
    // validation already prevents anyone else from acting on this player's
    // behalf - no explicit "freeze" bookkeeping is needed beyond not
    // accepting actions from a socket that no longer exists.
    entry.graceTimer = Timer(reconnectGracePeriod, () => _handlePlayerLeft(entry));
  }

  void _handlePlayerLeft(_RosterEntry entry) {
    if (entry.isConnected) return; // reconnected just before the timer fired
    // The engine has no concept of a player forfeiting or being skipped
    // indefinitely, so a seat that never comes back ends the session for
    // everyone. Tell them specifically who left, then tear down the same
    // way a deliberate host disconnect would (minus the redundant generic
    // message stop() would otherwise also send).
    _broadcastToAll(PlayerLeftMessage(entry.playerId));
    unawaited(stop(alreadyNotified: true));
  }

  /// Starts the game once the lobby has [minPlayers]..[maxPlayers] joined.
  /// Assigns each roster entry's already-minted `playerId` to `newGame` in
  /// join order (roster insertion order), sends each connected client its
  /// own [LobbyStartedMessage] carrying their reconnect token, then begins
  /// normal [StateMessage] broadcast.
  void startGame({int? seed}) {
    if (_gameStarted) {
      throw StateError('Game has already started');
    }
    if (_roster.length < minPlayers || _roster.length > maxPlayers) {
      throw StateError(
        'Need between $minPlayers and $maxPlayers players to start; have ${_roster.length}',
      );
    }

    _gameStarted = true;
    _state = newGame(
      playerNames: _roster.map((e) => e.displayName).toList(),
      seed: seed ?? DateTime.now().millisecondsSinceEpoch,
    );

    for (final entry in _roster) {
      _send(
        entry,
        LobbyStartedMessage(playerId: entry.playerId, sessionToken: entry.sessionToken),
      );
    }
    _broadcastState();
  }

  void _handleIncoming(_RosterEntry entry, dynamic raw) {
    final NetMessage message;
    try {
      message = NetMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
    } on FormatException catch (e) {
      _send(entry, ErrorMessage('Malformed message: ${e.message}'));
      return;
    }

    if (message is! ActionMessage) {
      _send(entry, const ErrorMessage('Only action messages are accepted'));
      return;
    }
    if (_state == null) {
      _send(entry, const ErrorMessage('Game has not started yet'));
      return;
    }

    // The client-declared playerId on the action must match the
    // connection's claimed identity - never trust a client to say who it
    // is acting as. applyAction then re-validates full game legality
    // (turn order, hand contents, target legality, ...) on top of that.
    if (message.action.playerId != entry.playerId) {
      _send(entry, const ErrorMessage('Action playerId does not match this connection'));
      return;
    }

    final result = applyAction(_state!, message.action);
    switch (result) {
      case ActionSuccess(:final state):
        _state = state;
        _broadcastState();
      case ActionFailure(:final reason):
        _send(entry, ErrorMessage(reason));
    }
  }

  void _broadcastRoster() {
    _broadcastToAll(LobbyRosterMessage(roster));
  }

  void _broadcastState() {
    for (final entry in _roster) {
      _sendStateTo(entry);
    }
  }

  void _sendStateTo(_RosterEntry entry) {
    if (_state == null) return;
    _send(entry, StateMessage(filterStateForPlayer(_state!, entry.playerId)));
  }

  void _broadcastToAll(NetMessage message) {
    for (final entry in _roster) {
      _send(entry, message);
    }
  }

  void _send(_RosterEntry entry, NetMessage message) {
    final socket = entry.socket;
    if (socket == null) return;
    // A socket can finish closing (its sink rejects further writes)
    // slightly before this entry's own onDone callback runs and nulls
    // entry.socket - most commonly when two clients disconnect around
    // the same time and one's teardown broadcasts to the other. That is
    // an ordinary, harmless race here: the peer is gone either way, so
    // there is nothing to notify.
    try {
      socket.add(jsonEncode(message.toJson()));
    } on StateError {
      // Sink already closed.
    }
  }

  String _mintToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Notifies every connected client the host is going away, cancels any
  /// pending grace timers, then closes all sockets and the listening
  /// server. Per the design, a host disconnect ends the session - there is
  /// no state persistence/resume.
  ///
  /// [alreadyNotified] skips the [HostDisconnectedMessage] broadcast: set
  /// by [_handlePlayerLeft], which already told clients specifically who
  /// left via [PlayerLeftMessage] and would otherwise send a second,
  /// redundant generic message right behind it.
  Future<void> stop({bool alreadyNotified = false}) async {
    // Idempotent: _handlePlayerLeft may already have stopped the server
    // by the time a caller's own teardown (e.g. addTearDown(host.stop) in
    // a test) runs stop() again - without this guard, the second call
    // would try to write to sockets its first call already closed.
    if (_stopped) return;
    _stopped = true;

    for (final entry in _roster) {
      entry.graceTimer?.cancel();
    }
    // Snapshot first: closing a socket triggers its own onDone handler,
    // which would otherwise mutate entry.socket / _roster mid-iteration.
    final sockets = [for (final e in _roster) e.socket].whereType<WebSocket>().toList();
    for (final socket in sockets) {
      try {
        if (!alreadyNotified) {
          socket.add(jsonEncode(const HostDisconnectedMessage().toJson()));
        }
        await socket.close();
      } on StateError {
        // Sink already closed - the peer is gone either way.
      }
    }
    await _httpServer?.close(force: true);
  }
}
