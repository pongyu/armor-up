import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:net/net.dart';

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
  hostDisconnected,
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

  /// Tears down any LAN plumbing and returns to the mode-select screen.
  /// Safe to call from any mode, including ones with no live
  /// server/client (hotseat).
  Future<void> returnToModeSelect() async {
    final current = state;
    await current.client?.close();
    await current.hostServer?.stop();
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
