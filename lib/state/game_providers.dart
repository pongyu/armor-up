import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_engine/game_engine.dart';

import 'game_controller.dart';

/// The current [GameState], or null if no game is in progress. Most UI
/// code should watch this rather than [gameControllerProvider] directly.
final gameStateProvider = Provider<GameState?>((ref) {
  return ref.watch(gameControllerProvider)?.state;
});

/// The most recent [ActionFailure] reason, if any, for a one-shot UI
/// notification (e.g. a SnackBar).
final gameErrorProvider = Provider<String?>((ref) {
  return ref.watch(gameControllerProvider)?.lastError;
});

/// True while an attack is awaiting a defense response.
final hasPendingInterruptProvider = Provider<bool>((ref) {
  return ref.watch(gameStateProvider)?.pendingInterrupt != null;
});

/// Convenience lookup for a [CardDef] by a [CardInstance]'s defId.
CardDef cardDefFor(CardInstance instance) => cardDefById(instance.defId);
