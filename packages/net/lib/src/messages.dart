import 'package:game_engine/game_engine.dart';

import 'action_codec.dart';
import 'filtered_state.dart';
import 'lobby.dart';

/// Base type for every message sent over the host<->client WebSocket.
/// Deliberately not sealed on the wire (JSON has no exhaustiveness check),
/// but the Dart-side type is a sealed class so `switch` on a decoded
/// message is exhaustiveness-checked once turned back into one of these.
sealed class NetMessage {
  const NetMessage();

  Map<String, dynamic> toJson();

  static NetMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) {
      throw FormatException('Malformed NetMessage JSON: $json');
    }
    switch (type) {
      case 'action':
        return ActionMessage(
          gameActionFromJson(json['action'] as Map<String, dynamic>),
        );
      case 'state':
        return StateMessage(
          FilteredGameState.fromJson(json['state'] as Map<String, dynamic>),
          responseDeadlineEpochMs: json['responseDeadlineEpochMs'] as int?,
        );
      case 'error':
        return ErrorMessage(json['reason'] as String);
      case 'hostDisconnected':
        return const HostDisconnectedMessage();
      case 'joinLobby':
        return JoinLobbyMessage(
          displayName: json['displayName'] as String?,
          rejoinPlayerId: json['rejoinPlayerId'] as String?,
          rejoinToken: json['rejoinToken'] as String?,
          avatar: json['avatar'] != null
              ? LobbyAvatar.fromJson(json['avatar'] as Map<String, dynamic>)
              : null,
        );
      case 'lobbyRoster':
        return LobbyRosterMessage(
          (json['players'] as List)
              .map((p) => LobbyPlayer.fromJson(p as Map<String, dynamic>))
              .toList(),
        );
      case 'lobbyStarted':
        return LobbyStartedMessage(
          playerId: json['playerId'] as String,
          sessionToken: json['sessionToken'] as String,
        );
      case 'joinRejected':
        return JoinRejectedMessage(json['reason'] as String);
      case 'playerLeft':
        return PlayerLeftMessage(json['playerId'] as String);
      default:
        throw FormatException('Unknown NetMessage type: $type');
    }
  }
}

/// Client -> host: "please apply this action on my behalf".
final class ActionMessage extends NetMessage {
  final GameAction action;

  const ActionMessage(this.action);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'action',
        'action': action.toJson(),
      };
}

/// Host -> one client: the authoritative state, already filtered down to
/// what that specific client is allowed to see.
///
/// [responseDeadlineEpochMs] is envelope-level (not part of [GameState] or
/// [FilteredGameState]) since it is wall-clock data: the epoch-millisecond
/// instant [HostServer]'s defense-response or group-discard timeout will
/// fire for the current pending actor, or null if no such deadline is
/// currently running (no pending interrupt/group-discard, or the deadline
/// mechanism is disabled/suppressed). Purely informational for a future
/// countdown UI - clients never act on it directly; only the host's own
/// timer actually enforces anything.
final class StateMessage extends NetMessage {
  final FilteredGameState state;
  final int? responseDeadlineEpochMs;

  const StateMessage(this.state, {this.responseDeadlineEpochMs});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'state',
        'state': state.toJson(),
        if (responseDeadlineEpochMs != null)
          'responseDeadlineEpochMs': responseDeadlineEpochMs,
      };
}

/// Host -> one client: their last [ActionMessage] was rejected by
/// [applyAction]. Carries the same human-readable reason
/// [ActionFailure.reason] would; state is unchanged.
final class ErrorMessage extends NetMessage {
  final String reason;

  const ErrorMessage(this.reason);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'error',
        'reason': reason,
      };
}

/// Host -> all clients, sent once right before the host closes its
/// listening socket / the host player leaves. Distinguishes a deliberate
/// "the game is over" close from an ordinary dropped connection so the UI
/// can show a clear message instead of a silent hang.
final class HostDisconnectedMessage extends NetMessage {
  const HostDisconnectedMessage();

  @override
  Map<String, dynamic> toJson() => {'type': 'hostDisconnected'};
}

/// Client -> host, sent immediately on connect, before a game exists.
/// Either a fresh join (only [displayName]/[avatar] set) or a reconnect
/// attempt (only [rejoinPlayerId]/[rejoinToken] set, presenting the
/// identity issued in a prior [LobbyStartedMessage]) - never both.
final class JoinLobbyMessage extends NetMessage {
  final String? displayName;
  final String? rejoinPlayerId;
  final String? rejoinToken;

  /// This client's chosen avatar look, sent on a fresh join so the host
  /// can include it in the [LobbyPlayer] roster entry it broadcasts. Not
  /// resent on reconnect - the host's roster entry already has it.
  final LobbyAvatar? avatar;

  const JoinLobbyMessage({
    this.displayName,
    this.rejoinPlayerId,
    this.rejoinToken,
    this.avatar,
  });

  bool get isReconnect => rejoinPlayerId != null;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'joinLobby',
        if (displayName != null) 'displayName': displayName,
        if (rejoinPlayerId != null) 'rejoinPlayerId': rejoinPlayerId,
        if (rejoinToken != null) 'rejoinToken': rejoinToken,
        if (avatar != null) 'avatar': avatar!.toJson(),
      };
}

/// Host -> all clients, broadcast whenever the lobby roster changes
/// (someone joins, or a game hasn't started yet and someone leaves).
final class LobbyRosterMessage extends NetMessage {
  final List<LobbyPlayer> players;

  const LobbyRosterMessage(this.players);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'lobbyRoster',
        'players': players.map((p) => p.toJson()).toList(),
      };
}

/// Host -> one client, sent individually once the host starts the game.
/// Carries that client's engine [playerId] and a session token to present
/// on a future reconnect (see [JoinLobbyMessage.rejoinToken]). After this,
/// [StateMessage]/[ActionMessage] flow as normal.
final class LobbyStartedMessage extends NetMessage {
  final String playerId;
  final String sessionToken;

  const LobbyStartedMessage({required this.playerId, required this.sessionToken});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'lobbyStarted',
        'playerId': playerId,
        'sessionToken': sessionToken,
      };
}

/// Host -> client: their [JoinLobbyMessage] (fresh join or reconnect) was
/// refused - lobby full, name collision, game already in progress with
/// joins closed, or an invalid/expired reconnect token.
final class JoinRejectedMessage extends NetMessage {
  final String reason;

  const JoinRejectedMessage(this.reason);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'joinRejected',
        'reason': reason,
      };
}

/// Host -> all clients: a connected player's reconnect grace period
/// expired without them returning, mid-game. Since the engine has no
/// concept of a player forfeiting, this ends the session for everyone,
/// the same as [HostDisconnectedMessage] - the game simply cannot
/// continue without them.
final class PlayerLeftMessage extends NetMessage {
  final String playerId;

  const PlayerLeftMessage(this.playerId);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'playerLeft',
        'playerId': playerId,
      };
}
