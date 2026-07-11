import 'package:game_engine/game_engine.dart';
import 'package:net/net.dart';
import 'package:test/test.dart';

Future<void> _waitUntil(bool Function() predicate) async {
  while (!predicate()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'a client that reconnects within the grace period resumes with current state',
    () async {
      final host = HostServer(
        hostDisplayName: 'Mumu',
        reconnectGracePeriod: const Duration(seconds: 5),
      );
      final port = await host.start();
      addTearDown(host.stop);

      final hostClient = GameClient();
      addTearDown(hostClient.close);
      await hostClient.connectToLobby('127.0.0.1', port, 'Mumu');

      final joiner = GameClient();
      await joiner.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);

      final hostStarted = hostClient.lobbyStarted.first;
      final joinerStarted = joiner.lobbyStarted.first;
      host.startGame(seed: 1);
      await hostStarted;
      await joinerStarted;

      final joinerPlayerId = joiner.playerId!;
      final joinerToken = joiner.sessionToken!;

      // p0 (host) draws a card so there's a state change to observe
      // resuming from after the reconnect.
      hostClient.dispatch(const DrawCard(playerId: 'p0'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Simulate the joiner's connection dropping (kill their socket
      // without a clean close() so the host sees onDone/onError exactly
      // like a real dropped phone connection).
      await joiner.close();
      await _waitUntil(
        () => host.roster.any((p) => p.playerId == joinerPlayerId),
      );

      final reconnected = GameClient();
      addTearDown(reconnected.close);
      final stateFuture = reconnected.states.first;
      await reconnected.reconnect('127.0.0.1', port, joinerPlayerId, joinerToken);

      final resumedState = await stateFuture;
      expect(resumedState.viewerId, joinerPlayerId);
      expect(resumedState.players.firstWhere((p) => p.id == 'p0').handSize, 6);
    },
  );

  test('reconnecting with a wrong token is rejected', () async {
    final host = HostServer(
      hostDisplayName: 'Mumu',
      reconnectGracePeriod: const Duration(seconds: 5),
    );
    final port = await host.start();
    addTearDown(host.stop);

    final hostClient = GameClient();
    addTearDown(hostClient.close);
    await hostClient.connectToLobby('127.0.0.1', port, 'Mumu');
    final joiner = GameClient();
    await joiner.connectToLobby('127.0.0.1', port, 'Zoe');
    await _waitUntil(() => host.roster.length == 2);

    final hostStarted = hostClient.lobbyStarted.first;
    final joinerStarted = joiner.lobbyStarted.first;
    host.startGame(seed: 1);
    await hostStarted;
    await joinerStarted;
    final joinerPlayerId = joiner.playerId!;

    await joiner.close();
    await _waitUntil(() => host.roster.length == 2);

    final impostor = GameClient();
    addTearDown(impostor.close);
    final rejection = impostor.joinRejected.first;
    await impostor.reconnect('127.0.0.1', port, joinerPlayerId, 'wrong-token');

    expect(await rejection, contains('Invalid or expired'));
  });

  test(
    'a seat that never reconnects within the grace period ends the session for everyone',
    () async {
      final host = HostServer(
        hostDisplayName: 'Mumu',
        reconnectGracePeriod: const Duration(milliseconds: 200),
      );
      final port = await host.start();
      addTearDown(host.stop);

      final hostClient = GameClient();
      addTearDown(hostClient.close);
      await hostClient.connectToLobby('127.0.0.1', port, 'Mumu');
      final joiner = GameClient();
      await joiner.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);

      final hostStarted = hostClient.lobbyStarted.first;
      final joinerStarted = joiner.lobbyStarted.first;
      host.startGame(seed: 1);
      await hostStarted;
      await joinerStarted;
      final joinerPlayerId = joiner.playerId!;

      final playerLeftFuture = hostClient.playerLeft.first;
      await joiner.close();

      final leftId = await playerLeftFuture.timeout(const Duration(seconds: 2));
      expect(leftId, joinerPlayerId);
    },
  );
}
