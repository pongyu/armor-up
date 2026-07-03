import 'dart:math';

/// Deterministic random source derived from a [GameState]'s seed and draw
/// count. Every call that consumes randomness must go through here and the
/// caller must persist the incremented draw count back onto the state, so
/// replaying the same seed + action sequence reproduces the same game.
final class GameRandom {
  final Random _random;
  int drawCount;

  GameRandom({required int seed, required int drawCount})
      : _random = Random(seed),
        drawCount = drawCount {
    // Fast-forward past previously consumed draws so re-hydrating a
    // GameState mid-replay continues the same deterministic sequence.
    for (var i = 0; i < drawCount; i++) {
      _random.nextInt(1 << 32);
    }
  }

  int nextInt(int max) {
    drawCount++;
    return _random.nextInt(max);
  }

  /// Fisher-Yates shuffle, consuming one draw per swap.
  List<T> shuffled<T>(List<T> input) {
    final list = [...input];
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}
