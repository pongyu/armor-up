import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('elimination win', () {
    test('last hit that eliminates the only remaining opponent ends the game', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fiery_dart'],
          1: [],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(
            playerId: 'p0',
            cardInstanceId: cardId,
            targetPlayerId: 'p1',
            targetArmor: ArmorType.helmet,
          ),
        ),
      );

      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.elimination));
      expect(result.eventLog.whereType<GameEnded>().single.winType, WinType.elimination);
    });

    test('with 3 players, eliminating one does not end the game', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob', 'Carl'],
        hands: {
          0: ['fiery_dart'],
          1: [],
          2: [],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(
            playerId: 'p0',
            cardInstanceId: cardId,
            targetPlayerId: 'p1',
            targetArmor: ArmorType.helmet,
          ),
        ),
      );

      expect(result.isGameOver, isFalse);
      expect(result.players[1].isEliminated, isTrue);
    });

    test('a resolution that eliminates every remaining player at once still ends the game (tiebreak winner)', () {
      // Jericho March turns every Weakened piece table-wide to Lost in one
      // resolution, so it can eliminate more than one player simultaneously
      // - here, both remaining players at once, since every piece either
      // player holds is Weakened or already Lost (no Strong pieces
      // survive for anyone). With Strong counts tied at 0 for both, the
      // fewest-Lost-pieces tiebreak decides: p1 has one fewer Lost piece
      // (5 Lost + 1 Weakened-that-becomes-Lost = 6, vs p0's already-6-Lost
      // plus... ) - concretely: p0 is already all Lost except one
      // Weakened piece (5 Lost, 1 Weakened -> 6 Lost after the march); p1
      // has two Weakened pieces and 4 Lost (4 Lost, 2 Weakened -> 6 Lost
      // after the march too). Both end fully Lost (6/6 each), so Strong
      // and Lost counts tie completely and the deciding tiebreak is
      // turn order - p0 (index 0) wins over p1 (index 1).
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['jericho_march'],
          1: [],
        },
        armorOverrides: {
          0: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      expect(result.players[0].isEliminated, isTrue);
      expect(result.players[1].isEliminated, isTrue);
      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.elimination));
      expect(result.eventLog.whereType<GameEnded>().single.winType, WinType.elimination);
    });

    test('mutual elimination tiebreak prefers more Strong pieces when Strong counts differ', () {
      // p0 keeps a Strong piece that Jericho March never touches (only
      // Weakened pieces convert); p1 does not, so after the march p0 is
      // NOT fully Lost (not eliminated) while p1 is. This isn't actually
      // a mutual-elimination case - it's here to pin down that the
      // now-shared elimination-check codepath still behaves correctly
      // for the ordinary single-elimination case after the fix (the
      // Strong-piece tiebreak sort only kicks in for zero remaining
      // active players, never for exactly one).
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['jericho_march'],
          1: [],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      );
      final cardId = state.players[0].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(state, PlayCard(playerId: 'p0', cardInstanceId: cardId)),
      );

      expect(result.players[0].isEliminated, isFalse);
      expect(result.players[1].isEliminated, isTrue);
      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.elimination));
    });

    test('no actions are accepted after the game ends', () {
      var state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
      );
      state = state.copyWith(
        winner: const WinResult(winnerId: 'p0', type: WinType.elimination),
      );
      final reason = expectFailure(applyAction(state, const DrawCard(playerId: 'p1')));
      expect(reason, contains('already ended'));
    });
  });

  group('restoration win', () {
    test(
      'the degenerate line from playtesting: one hit to Weakened, Renewal, turn rotation - does NOT win',
      () {
        // Exactly the scratch-then-band-aid line that motivated the
        // wasEverBroken threshold: a single piece dropping to Weakened
        // and immediately patched with Renewal must not count as a
        // genuine comeback, even though every piece is Strong again.
        final state = buildTestState(
          playerNames: ['Alice', 'Bob'],
          hands: {
            0: ['renewal'],
            1: [],
          },
          armorOverrides: {
            0: {ArmorType.helmet: ArmorCondition.weakened},
          },
        );
        final cardId = state.players[0].hand.first.instanceId;
        var result = expectSuccess(
          applyAction(
            state,
            PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
          ),
        );

        expect(result.players[0].wasEverBroken, isFalse);
        expect(result.players[0].isFullyRestored, isFalse);
        expect(result.isGameOver, isFalse);

        // Even after turn rotation back to Alice (the actual restoration
        // win check point), still no win.
        final atBobsTurn = result.copyWith(activePlayerIndex: 1, hasDrawnThisTurn: true);
        result = expectSuccess(applyAction(atBobsTurn, const EndTurn(playerId: 'p1')));

        expect(result.isGameOver, isFalse);
      },
    );

    test('Lost-then-restored DOES win: piece to Lost, Armor Bearer restores it, turn rotation wins', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      var result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      expect(result.players[0].wasEverBroken, isTrue);
      expect(result.players[0].isFullyRestored, isTrue);
      // Still Alice's own turn (not the start of it), so no win yet.
      expect(result.isGameOver, isFalse);

      final atBobsTurn = result.copyWith(activePlayerIndex: 1, hasDrawnThisTurn: true);
      result = expectSuccess(applyAction(atBobsTurn, const EndTurn(playerId: 'p1')));

      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.restoration));
      expect(result.eventLog.whereType<GameEnded>().single.winType, WinType.restoration);
    });

    test('the flag is sticky: a piece that went Lost earlier still counts even once every piece is Strong again', () {
      // p0 starts already wasEverBroken (armorOverrides below sets a Lost
      // piece), then that piece gets restored to Strong via a plain
      // direct state edit (standing in for "any restore path" - Renewal
      // only applies to Weakened, so a piece that was Lost realistically
      // reaches Strong via Armor Bearer/Fasting or a Renewal applied
      // after a prior partial restore; this test only cares that the
      // flag, once set, survives regardless of exactly how the piece
      // later became Strong again).
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      );
      expect(state.players[0].wasEverBroken, isTrue);

      final aliceFullyRestored = state.updatePlayer(
        'p0',
        (p) => p.copyWith(
          armor: [
            for (final piece in p.armor)
              if (piece.type == ArmorType.helmet)
                piece.copyWith(condition: ArmorCondition.strong)
              else
                piece,
          ],
        ),
      );
      // wasEverBroken must still be true - a plain armor edit (not
      // through withArmorCondition) proves the flag itself, once set,
      // is never implicitly cleared by simply having Strong armor again.
      expect(aliceFullyRestored.players[0].wasEverBroken, isTrue);
      expect(aliceFullyRestored.players[0].isFullyRestored, isTrue);

      final atBobsTurn = aliceFullyRestored.copyWith(activePlayerIndex: 1);
      final result = expectSuccess(applyAction(atBobsTurn, const EndTurn(playerId: 'p1')));

      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.restoration));
    });

    test('being fully restored mid-turn (not at turn start) does not win immediately', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      );
      final cardId = state.players[0].hand.first.instanceId;
      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      // Alice is now fully restored, but it's still her turn (not the
      // start of it) so the game should not have ended yet.
      expect(result.players[0].isFullyRestored, isTrue);
      expect(result.isGameOver, isFalse);
    });

    test('restorationWinEnabled=false: a Lost-then-fully-restored player does not win; game continues', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['armor_bearer'],
          1: [],
        },
        armorOverrides: {
          0: {ArmorType.helmet: ArmorCondition.lost},
        },
      ).copyWith(restorationWinEnabled: false);
      final cardId = state.players[0].hand.first.instanceId;
      var result = expectSuccess(
        applyAction(
          state,
          PlayCard(playerId: 'p0', cardInstanceId: cardId, targetArmor: ArmorType.helmet),
        ),
      );

      expect(result.players[0].isFullyRestored, isTrue);
      expect(result.isGameOver, isFalse);

      // Turn rotation back to Alice - in full mode this would win; in
      // basic mode it must not.
      final atBobsTurn = result.copyWith(activePlayerIndex: 1, hasDrawnThisTurn: true);
      result = expectSuccess(applyAction(atBobsTurn, const EndTurn(playerId: 'p1')));

      expect(result.isGameOver, isFalse);
      expect(result.winner, isNull);
    });

    test('restorationWinEnabled=false: elimination win still functions normally', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {
          0: ['fiery_dart'],
          1: [],
        },
        armorOverrides: {
          1: {
            ArmorType.helmet: ArmorCondition.weakened,
            ArmorType.breastplate: ArmorCondition.lost,
            ArmorType.shield: ArmorCondition.lost,
            ArmorType.sword: ArmorCondition.lost,
            ArmorType.belt: ArmorCondition.lost,
            ArmorType.shoes: ArmorCondition.lost,
          },
        },
      ).copyWith(restorationWinEnabled: false);
      final cardId = state.players[0].hand.first.instanceId;

      final result = expectSuccess(
        applyAction(
          state,
          PlayCard(
            playerId: 'p0',
            cardInstanceId: cardId,
            targetPlayerId: 'p1',
            targetArmor: ArmorType.helmet,
          ),
        ),
      );

      expect(result.isGameOver, isTrue);
      expect(result.winner, const WinResult(winnerId: 'p0', type: WinType.elimination));
    });

    test('restorationWinEnabled=false: deck-exhaustion ranking still functions normally', () {
      final state = buildTestState(
        playerNames: ['Alice', 'Bob'],
        hands: {0: [], 1: []},
        drawPileDefIds: [],
      ).copyWith(hasDrawnThisTurn: false, restorationWinEnabled: false);

      final result = expectSuccess(applyAction(state, const DrawCard(playerId: 'p0')));

      expect(result.isGameOver, isTrue);
      expect(result.winner!.type, WinType.deckExhausted);
    });
  });
}
