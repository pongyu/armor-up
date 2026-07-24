import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:net/net.dart';

import '../net/reconnect_info.dart';
import '../widgets/pixel_ui.dart';
import 'game_controller.dart';
import 'net_game_controller.dart';

/// Which top-level flow the app is currently in. Orthogonal to whether a
/// game is in progress ([GameUiState] handles that) - this tracks how the
/// player got there and what screen should be showing before/around it.
enum AppMode {
  /// First screen: choose hotseat vs. LAN.
  modeSelect,

  /// Local pass-and-play: name entry ([SetupScreen], unchanged) and, once
  /// [gameControllerProvider] holds a state, actual play. Both are one
  /// mode value because the transition between them is (as it always
  /// was) purely driven by whether a [GameState] exists, not a separate
  /// mode change `SetupScreen` would otherwise need to remember to call.
  hotseatSetup,

  /// This device is about to host: enter a display name and game name,
  /// before [HostServer] is created.
  hostSetup,

  /// This device is hosting: [HostServer] is running, lobby is open, game
  /// hasn't started.
  hostLobby,

  /// This device is joining: discovery/manual-entry screen, not yet
  /// connected to a lobby.
  joinFlow,

  /// Connected to a lobby as a non-host, waiting for the host to start.
  waitingForHost,

  /// LAN game in progress, backed by [netGameControllerProvider].
  netPlaying,

  /// The host ended the session (deliberately, or a seat's grace period
  /// expired) - shown until the player backs out to [modeSelect].
  /// Unrecoverable - unlike [connectionLost], there is nothing a retry
  /// could fix.
  hostDisconnected,

  /// This device's own [GameClient] socket dropped unexpectedly (see
  /// [GameClient.connectionLost]) without the host having said the session
  /// is over - the host may still be running and the seat may still be
  /// held during its reconnect grace period. Shown with a manual
  /// "Reconnect" action (see `ConnectionLostScreen`) rather than treating
  /// this the same as [hostDisconnected].
  connectionLost,
}

/// Tracks [AppMode] plus whatever LAN plumbing (host server / client) is
/// live for the current flow, so screens can reach the same
/// [HostServer]/[GameClient] instance across rebuilds instead of each
/// screen creating its own.
class AppModeState {
  final AppMode mode;
  final HostServer? hostServer;
  final GameClient? client;
  final String? hostDisconnectedReason;

  const AppModeState({
    required this.mode,
    this.hostServer,
    this.client,
    this.hostDisconnectedReason,
  });

  AppModeState copyWith({
    AppMode? mode,
    HostServer? hostServer,
    bool clearHostServer = false,
    GameClient? client,
    bool clearClient = false,
    String? hostDisconnectedReason,
  }) =>
      AppModeState(
        mode: mode ?? this.mode,
        hostServer: clearHostServer ? null : (hostServer ?? this.hostServer),
        client: clearClient ? null : (client ?? this.client),
        hostDisconnectedReason: hostDisconnectedReason ?? this.hostDisconnectedReason,
      );
}

class AppModeController extends StateNotifier<AppModeState> {
  AppModeController() : super(const AppModeState(mode: AppMode.modeSelect));

  void chooseHotseat() => state = state.copyWith(mode: AppMode.hotseatSetup);

  void enterHostSetup() => state = const AppModeState(mode: AppMode.hostSetup);

  void enterHostLobby(HostServer server, GameClient hostPlayerClient) {
    state = AppModeState(
      mode: AppMode.hostLobby,
      hostServer: server,
      client: hostPlayerClient,
    );
  }

  void enterJoinFlow() => state = const AppModeState(mode: AppMode.joinFlow);

  void enterWaitingForHost(GameClient client) {
    state = AppModeState(mode: AppMode.waitingForHost, client: client);
  }

  /// Called once [GameClient.lobbyStarted] fires, whether this device is
  /// the host or a joiner - both watch the same event to move from their
  /// respective lobby screen into actual gameplay.
  void enterNetPlaying() {
    state = state.copyWith(mode: AppMode.netPlaying);
  }

  void hostDisconnected(String reason) {
    state = AppModeState(mode: AppMode.hostDisconnected, hostDisconnectedReason: reason);
  }

  /// This device's own [GameClient] socket dropped unexpectedly (see
  /// [AppMode.connectionLost]'s doc comment). Keeps [AppModeState.client]
  /// and [AppModeState.hostServer] around - the same [GameClient] is what
  /// `ConnectionLostScreen`'s Reconnect button calls `reconnect` on, and a
  /// host whose own loopback client drops must not have its still-running
  /// [HostServer] torn down out from under the other connected players.
  void connectionLost() {
    state = state.copyWith(mode: AppMode.connectionLost);
  }

  /// Cold-start equivalent of [connectionLost]: the app relaunched with a
  /// [ReconnectInfo] still saved from a prior process, so it never went
  /// through [enterWaitingForHost]/[enterHostLobby] to get a [client] in
  /// the first place. [client] is a freshly constructed, not-yet-connected
  /// [GameClient] for `ConnectionLostScreen`'s Reconnect button to call
  /// `reconnect` on (using the persisted info, since this client has none
  /// of its own yet).
  void resumeFromColdStart(GameClient client) {
    state = AppModeState(mode: AppMode.connectionLost, client: client);
  }

  /// Called after `GameClient.reconnect` succeeds, to leave
  /// [AppMode.connectionLost] and resume wherever the session actually is
  /// - back in the lobby if the host hadn't started the game yet, or
  /// straight back into gameplay (mirroring `_AppRoot`'s normal
  /// `whenStarted` transition) if it had.
  void resumeAfterReconnect({required bool gameStarted}) {
    state = state.copyWith(mode: gameStarted ? AppMode.netPlaying : AppMode.waitingForHost);
  }

  /// Tears down any LAN plumbing and returns to the mode-select screen.
  /// Safe to call from any mode, including ones with no live
  /// server/client (hotseat).
  Future<void> returnToModeSelect() async {
    final current = state;
    await current.client?.close();
    await current.hostServer?.stop();
    await ReconnectInfo.clear();
    state = const AppModeState(mode: AppMode.modeSelect);
  }
}

final appModeControllerProvider =
    StateNotifierProvider<AppModeController, AppModeState>((ref) => AppModeController());

/// The controller that should currently receive dispatched
/// [GameAction]s/clearError calls: [GameController] in hotseat mode,
/// [NetGameController] in LAN mode. Screens that used to call
/// `ref.read(gameControllerProvider.notifier)` directly call
/// `ref.read(activeGameControllerProvider)` instead - same `dispatch`/
/// `clearError` shape either way, so no other screen logic changes.
final activeGameControllerProvider = Provider<GameActionDispatcher>((ref) {
  final mode = ref.watch(appModeControllerProvider).mode;
  return mode == AppMode.netPlaying
      ? ref.read(netGameControllerProvider.notifier)
      : ref.read(gameControllerProvider.notifier);
});

/// Maps engine player id -> chosen avatar look for every LAN player who
/// customized one, sourced from the current [AppModeState.client]'s lobby
/// roster (see `LobbyPlayer.avatar`). The roster is only ever broadcast
/// during the lobby phase, but [GameClient.latestRoster] retains the last
/// broadcast - which already has everyone, host included - for the rest of
/// the session, so this stays valid once gameplay starts. Empty in hotseat
/// mode (no client) or when nobody customized an avatar; callers should
/// fall back to the seed-derived look on a miss, same as hotseat opponents
/// always have.
final lanAvatarsProvider = Provider<Map<String, AvatarPalette>>((ref) {
  final client = ref.watch(appModeControllerProvider).client;
  if (client == null) return const {};
  // Rebuild whenever the roster changes (e.g. a player joins after this
  // provider is first read) - AsyncValue.data seeds synchronously from
  // client.latestRoster via the initial event a StreamProvider re-emits,
  // but we drive this off the raw stream directly to avoid an extra
  // provider just for that plumbing.
  final roster = ref.watch(_lanRosterProvider).valueOrNull ?? client.latestRoster;
  return {
    for (final player in roster)
      if (player.avatar != null) player.playerId: AvatarPalette.fromLobbyAvatar(player.avatar!),
  };
});

final _lanRosterProvider = StreamProvider<List<LobbyPlayer>>((ref) {
  final client = ref.watch(appModeControllerProvider).client;
  if (client == null) return const Stream.empty();
  return client.lobbyRoster;
});
