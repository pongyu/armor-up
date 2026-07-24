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
  final LobbyAvatar? avatar;
  WebSocket? socket;
  Timer? graceTimer;

  _RosterEntry({
    required this.playerId,
    required this.displayName,
    required this.sessionToken,
    this.avatar,
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

  /// How long a connected-but-idle player is given to respond to a pending
  /// defense interrupt or group-discard obligation before the host acts on
  /// their behalf (a system [DeclineDefense] or a random [DiscardCard]).
  /// Null disables the mechanism entirely (the table waits forever, as
  /// before this feature). Applies only while the current actor's socket
  /// is connected - see [_responseTimer] for the interaction with
  /// [reconnectGracePeriod].
  final Duration? defenseResponseTimeout;

  /// The player id the response timer is currently running for (the
  /// current pending-interrupt or group-discard actor at the time the
  /// timer was last (re)started), so a broadcast can tell whether the
  /// actor changed and the timer needs restarting. Null when no timer is
  /// running (no pending obligation, or it's suppressed - see
  /// [_syncResponseTimer]).
  String? _responseTimerActorId;
  Timer? _responseTimer;
  DateTime? _responseDeadline;

  HostServer({
    required this.hostDisplayName,
    this.reconnectGracePeriod = const Duration(seconds: 60),
    this.defenseResponseTimeout = const Duration(seconds: 20),
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The authoritative state once [startGame] has been called; null during
  /// the lobby phase.
  GameState? get state => _state;

  /// The current lobby roster (also valid, unchanging in membership, after
  /// the game has started).
  List<LobbyPlayer> get roster => [
        for (final entry in _roster)
          LobbyPlayer(
            playerId: entry.playerId,
            displayName: entry.displayName,
            avatar: entry.avatar,
          ),
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
      _handleFreshJoin(socket, route, message.displayName ?? '', message.avatar);
    }
  }

  void _handleFreshJoin(
    WebSocket socket,
    _SocketRoute route,
    String displayName,
    LobbyAvatar? avatar,
  ) {
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
      avatar: avatar,
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
      // Reconnecting flips this seat from "no timer" (suppressed while
      // disconnected) back to a fresh deadline if they're the current
      // pending actor - run before _sendStateTo so the deadline in the
      // state this client receives is the newly (re)started one, not
      // stale/absent.
      _syncResponseTimer();
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

    // If the response timer was running for this now-disconnected player,
    // suppress it in favor of reconnectGracePeriod (a connected-but-idle
    // player is a very different situation from one who dropped
    // entirely) - reconnecting will start a fresh deadline for them.
    _syncResponseTimer();
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
  ///
  /// [restorationWinEnabled] and [maxReshuffles] default to `newGame`'s own
  /// defaults (full mode, unlimited reshuffles) - no lobby UI exposes
  /// either yet, so LAN games always start in that default configuration
  /// until a later UI pass adds a lobby-side toggle.
  void startGame({int? seed, bool restorationWinEnabled = true, int? maxReshuffles}) {
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
      restorationWinEnabled: restorationWinEnabled,
      maxReshuffles: maxReshuffles,
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
    _syncResponseTimer();
    for (final entry in _roster) {
      _sendStateTo(entry);
    }
  }

  void _sendStateTo(_RosterEntry entry) {
    if (_state == null) return;
    _send(
      entry,
      StateMessage(
        filterStateForPlayer(
          _state!,
          entry.playerId,
          connectedPlayerIds: {
            for (final e in _roster)
              if (e.isConnected) e.playerId,
          },
        ),
        responseDeadlineEpochMs: _responseDeadline?.millisecondsSinceEpoch,
      ),
    );
  }

  /// The player id whose response the engine is currently waiting on for a
  /// pending defense interrupt or group-discard obligation, or null if
  /// neither is outstanding. Mirrors `currentActorId` in the Flutter app's
  /// `lib/state/turn_actor.dart` (not reachable from this package), scoped
  /// to just the two obligations the response timer cares about - normal
  /// turn-order play (draw/play/end turn) has no per-actor deadline.
  String? _currentPendingActorId(GameState state) {
    final groupDiscard = state.pendingGroupDiscard;
    if (groupDiscard != null) {
      return groupDiscard.owedPlayerIds.first;
    }

    final pending = state.pendingInterrupt;
    if (pending == null) return null;

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

  /// (Re)starts, suppresses, or cancels the response-deadline timer to
  /// match the current state, called after every state transition
  /// ([_broadcastState]) and every connect/disconnect ([_listenOn] /
  /// [_handleDisconnect]) that could change who the timer should be
  /// running for or whether it should be running at all.
  ///
  /// A fresh timer is (re)started whenever the current pending actor
  /// differs from who it was last running for (a brand new interrupt, or
  /// a Fellowship request passing to the next helper) - restarting on
  /// every call would let a chatty client indefinitely postpone a
  /// deadline by causing unrelated broadcasts, but the actor only changes
  /// at exactly the moments the spec calls for a restart. Suppressed
  /// entirely while that actor's socket is disconnected (their own
  /// [reconnectGracePeriod] governs that case instead - see
  /// [_handleDisconnect]); reconnecting restarts the deadline fresh via
  /// the same actor-changed check failing to short-circuit next time
  /// [_syncResponseTimer] runs, since [_responseTimerActorId] is cleared
  /// by [_cancelResponseTimer] when disconnection suppresses the timer.
  void _syncResponseTimer() {
    final timeout = defenseResponseTimeout;
    final state = _state;
    if (timeout == null || state == null) {
      _cancelResponseTimer();
      return;
    }

    final actorId = _currentPendingActorId(state);
    if (actorId == null) {
      _cancelResponseTimer();
      return;
    }

    final entry = _roster.where((e) => e.playerId == actorId).firstOrNull;
    if (entry == null || !entry.isConnected) {
      // Disconnected (or, defensively, unknown) actor: the reconnect
      // grace period governs this seat instead: no response timer while
      // there is nobody there to respond. Reconnecting will observe the
      // actor "changed" (from suppressed back to active) on the next
      // sync and start a fresh deadline.
      _cancelResponseTimer();
      return;
    }

    if (_responseTimerActorId == actorId) {
      // Same actor as last sync - an in-flight timer (if any) already
      // covers them; leave its original deadline alone.
      return;
    }

    _responseTimer?.cancel();
    _responseTimerActorId = actorId;
    _responseDeadline = DateTime.now().add(timeout);
    _responseTimer = Timer(timeout, () => _handleResponseTimeout(actorId));
  }

  void _cancelResponseTimer() {
    _responseTimer?.cancel();
    _responseTimer = null;
    _responseTimerActorId = null;
    _responseDeadline = null;
  }

  /// Fires when [actorId] fails to respond to a pending defense interrupt
  /// or group-discard obligation within [defenseResponseTimeout]. Applies
  /// a system action through the normal [applyAction] path - identical
  /// legality/resolution rules as if the player had acted themselves - and
  /// broadcasts the result, which in turn re-syncs the timer for whatever
  /// obligation (if any) is outstanding next.
  void _handleResponseTimeout(String actorId) {
    // The obligation may have already resolved (e.g. the player responded
    // in the instant before the timer fired, racing the cancel in
    // _syncResponseTimer) or the actor may no longer be who the timer was
    // started for (a broadcast already moved the obligation on). Either
    // way there is nothing to force.
    if (_responseTimerActorId != actorId) return;
    final state = _state;
    if (state == null) return;
    if (_currentPendingActorId(state) != actorId) return;

    final GameAction systemAction;
    if (state.pendingGroupDiscard != null) {
      final hand = state.playerById(actorId).hand;
      // A stalled group discard always has at least one owed player with
      // a non-empty hand (resolveEffect only ever adds players who have
      // cards to owedPlayerIds, and owedPlayerIds shrinks to null the
      // instant it's empty), so hand is guaranteed non-empty here.
      final randomIndex = _random.nextInt(hand.length);
      systemAction = DiscardCard(
        playerId: actorId,
        cardInstanceId: hand[randomIndex].instanceId,
      );
    } else {
      systemAction = DeclineDefense(playerId: actorId, isSystemDecline: true);
    }

    final result = applyAction(state, systemAction);
    switch (result) {
      case ActionSuccess(:final state):
        _state = state;
        _broadcastState();
      case ActionFailure():
        // The engine itself refused the system action (should not happen
        // given the actor/obligation checks above, but fail safe rather
        // than throw from a timer callback): drop the timer so a stuck
        // obligation doesn't spin retrying the same rejected action.
        _cancelResponseTimer();
    }
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

    _cancelResponseTimer();
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
