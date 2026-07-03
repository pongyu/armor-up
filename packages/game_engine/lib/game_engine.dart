/// Pure Dart rules engine for Armor Up!.
///
/// This package has no Flutter or network dependencies. All player input
/// flows through [applyAction], so a future networked client can drive the
/// exact same engine used by the hotseat UI.
library;

export 'src/action_result.dart';
export 'src/actions/game_action.dart';
export 'src/deck.dart';
export 'src/effects.dart' show landPendingAttack;
export 'src/engine.dart';
export 'src/models/armor.dart';
export 'src/models/card.dart';
export 'src/models/game_event.dart';
export 'src/models/game_state.dart';
export 'src/models/pending_interrupt.dart';
export 'src/models/player.dart';
export 'src/models/win_result.dart';
export 'src/rng.dart';
export 'src/setup.dart';
