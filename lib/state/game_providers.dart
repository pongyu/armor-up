import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';

import 'app_mode_controller.dart';
import 'game_controller.dart';
import 'net_game_controller.dart';

/// The current [GameState], or null if no game is in progress. Backed by
/// [gameControllerProvider] in hotseat mode or [netGameControllerProvider]
/// in LAN mode - both expose the same [GameUiState] shape (the LAN side
/// via `reconstructFromFiltered`), so every widget built against this
/// provider works unmodified in either mode.
final gameStateProvider = Provider<GameState?>((ref) {
  final mode = ref.watch(appModeControllerProvider).mode;
  final uiState = mode == AppMode.netPlaying
      ? ref.watch(netGameControllerProvider)
      : ref.watch(gameControllerProvider);
  return uiState?.state;
});

/// The most recent [ActionFailure] reason, if any, for a one-shot UI
/// notification (e.g. a SnackBar).
final gameErrorProvider = Provider<String?>((ref) {
  final mode = ref.watch(appModeControllerProvider).mode;
  final uiState = mode == AppMode.netPlaying
      ? ref.watch(netGameControllerProvider)
      : ref.watch(gameControllerProvider);
  return uiState?.lastError;
});

/// True while an attack is awaiting a defense response.
final hasPendingInterruptProvider = Provider<bool>((ref) {
  return ref.watch(gameStateProvider)?.pendingInterrupt != null;
});

/// The epoch-millisecond instant the host's defense-response/group-discard
/// timeout will fire for the current pending actor, or null if none is
/// running - see [GameUiState.responseDeadlineEpochMs]. Always null in
/// hotseat mode (mirrors [localPlayerIdProvider]'s gating, since hotseat's
/// [GameController] has no host/timer concept at all).
final responseDeadlineEpochMsProvider = Provider<int?>((ref) {
  final mode = ref.watch(appModeControllerProvider).mode;
  if (mode != AppMode.netPlaying) return null;
  return ref.watch(netGameControllerProvider)?.responseDeadlineEpochMs;
});

/// In LAN mode, this device's own engine player id - the player whose
/// hand/board this device must always render, regardless of whose turn it
/// is. Null in hotseat mode, where there is no single "local" player and
/// the board follows whoever is currently acting (`currentActorId`)
/// behind a pass-the-device gate instead.
final localPlayerIdProvider = Provider<String?>((ref) {
  final mode = ref.watch(appModeControllerProvider).mode;
  if (mode != AppMode.netPlaying) return null;
  // Depend on the net UI state so this re-evaluates once attach() has run
  // and playerId is available.
  ref.watch(netGameControllerProvider);
  return ref.read(netGameControllerProvider.notifier).localPlayerId;
});

/// Convenience lookup for a [CardDef] by a [CardInstance]'s defId.
CardDef cardDefFor(CardInstance instance) => cardDefById(instance.defId);
