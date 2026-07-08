import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';
import 'package:test/test.dart';

/// Collects every state a [GameClient] receives from the moment this is
/// called, so tests can assert on a specific later state without racing
/// a broadcast stream (which never replays past events to a listener
/// that subscribes late).
class _StateSpy {
  final List<FilteredGameState> received = [];

  _StateSpy(GameClient client) {
    client.states.listen(received.add);
  }

  Future<FilteredGameState> waitFor(
    bool Function(FilteredGameState) predicate,
  ) async {
    while (!received.any(predicate)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return received.lastWhere(predicate);
  }
}

Future<void> _waitUntil(bool Function() predicate) async {
  while (!predicate()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'lobby join through to gameplay: client draws a card over a real '
    'WebSocket and both sides converge on the same state',
    () async {
      final host = HostServer(hostDisplayName: 'Mumu');
      final port = await host.start();
      addTearDown(host.stop);

      // p0 is the host's own local player; p1 is a second device joining
      // over the network. Both go through the same lobby -> gameplay path
      // a real phone would, including the host device playing too, not
      // just serving.
      final hostPlayerClient = GameClient();
      addTearDown(hostPlayerClient.close);
      await hostPlayerClient.connectToLobby('127.0.0.1', port, 'Mumu');

      final joinerClient = GameClient();
      addTearDown(joinerClient.close);
      await joinerClient.connectToLobby('127.0.0.1', port, 'Zoe');

      await _waitUntil(() => host.roster.length == 2);
      expect(host.roster.map((p) => p.displayName), ['Mumu', 'Zoe']);

      final hostStartedFuture = hostPlayerClient.lobbyStarted.first;
      final joinerStartedFuture = joinerClient.lobbyStarted.first;
      host.startGame(seed: 99);
      await hostStartedFuture;
      await joinerStartedFuture;

      expect(hostPlayerClient.playerId, 'p0');
      expect(joinerClient.playerId, 'p1');

      final hostPlayerStates = _StateSpy(hostPlayerClient);
      final joinerStates = _StateSpy(joinerClient);

      final initialJoinerView = await joinerStates.waitFor((_) => true);
      expect(initialJoinerView.viewerId, 'p1');
      expect(initialJoinerView.turnNumber, 1);
      expect(
        initialJoinerView.players.firstWhere((p) => p.id == 'p1').hand?.length,
        5,
      );

      // p0 draws (hand goes to 6, over the 5-card limit), discards back
      // down to the limit, then ends their turn - all three actions sent
      // over the wire, mirroring exactly what the hotseat UI requires.
      hostPlayerClient.dispatch(const DrawCard(playerId: 'p0'));
      final p0AfterDraw =
          await hostPlayerStates.waitFor((s) => s.hasDrawnThisTurn);
      final p0Hand =
          p0AfterDraw.players.firstWhere((p) => p.id == 'p0').hand!;

      hostPlayerClient.dispatch(
        DiscardCard(playerId: 'p0', cardInstanceId: p0Hand.first.instanceId),
      );
      await hostPlayerStates.waitFor(
        (s) => s.players.firstWhere((p) => p.id == 'p0').hand!.length == 5,
      );

      hostPlayerClient.dispatch(const EndTurn(playerId: 'p0'));
      final turnTwoView = await joinerStates.waitFor((s) => s.turnNumber == 2);
      expect(turnTwoView.hasDrawnThisTurn, isFalse);

      // The action under test: p1 draws a card via its own client, over
      // the real socket, validated by the host's applyAction, and
      // broadcast back to both connected devices.
      joinerClient.dispatch(const DrawCard(playerId: 'p1'));
      final afterDraw =
          await joinerStates.waitFor((s) => s.turnNumber == 2 && s.hasDrawnThisTurn);

      final p1View = afterDraw.players.firstWhere((p) => p.id == 'p1');
      expect(p1View.hand!.length, 6);

      // The host's own authoritative state (what the host device renders)
      // agrees with what the joiner's client received.
      expect(host.state!.playerById('p1').hand.length, p1View.hand!.length);
      expect(host.state!.turnNumber, afterDraw.turnNumber);
    },
  );
}
