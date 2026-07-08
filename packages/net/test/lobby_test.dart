import 'package:net/net.dart';
import 'package:test/test.dart';

Future<void> _waitUntil(bool Function() predicate) async {
  while (!predicate()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('roster broadcasts to every connected client as players join', () async {
    final host = HostServer(hostDisplayName: 'Mumu');
    final port = await host.start();
    addTearDown(host.stop);

    final a = GameClient();
    addTearDown(a.close);
    final aRosters = <List<LobbyPlayer>>[];
    a.lobbyRoster.listen(aRosters.add);
    await a.connectToLobby('127.0.0.1', port, 'Mumu');
    await _waitUntil(() => aRosters.isNotEmpty);
    expect(aRosters.last.map((p) => p.displayName), ['Mumu']);

    final b = GameClient();
    addTearDown(b.close);
    final bRosters = <List<LobbyPlayer>>[];
    b.lobbyRoster.listen(bRosters.add);
    await b.connectToLobby('127.0.0.1', port, 'Zoe');

    await _waitUntil(() => aRosters.last.length == 2);
    expect(aRosters.last.map((p) => p.displayName), ['Mumu', 'Zoe']);
    await _waitUntil(() => bRosters.isNotEmpty && bRosters.last.length == 2);
    expect(bRosters.last.map((p) => p.displayName), ['Mumu', 'Zoe']);
  });

  test('startGame sends each client its own playerId and turn-1 state', () async {
    final host = HostServer(hostDisplayName: 'Mumu');
    final port = await host.start();
    addTearDown(host.stop);

    final clients = [GameClient(), GameClient(), GameClient()];
    for (final c in clients) {
      addTearDown(c.close);
    }
    await clients[0].connectToLobby('127.0.0.1', port, 'Mumu');
    await clients[1].connectToLobby('127.0.0.1', port, 'Zoe');
    await clients[2].connectToLobby('127.0.0.1', port, 'Sam');
    await _waitUntil(() => host.roster.length == 3);

    final startedFutures = [for (final c in clients) c.lobbyStarted.first];
    final firstStates = [for (final c in clients) c.states.first];
    host.startGame(seed: 1);
    await Future.wait(startedFutures);

    expect(clients[0].playerId, 'p0');
    expect(clients[1].playerId, 'p1');
    expect(clients[2].playerId, 'p2');
    for (final c in clients) {
      expect(c.sessionToken, isNotNull);
    }

    final states = await Future.wait(firstStates);
    for (var i = 0; i < states.length; i++) {
      expect(states[i].viewerId, clients[i].playerId);
      expect(states[i].turnNumber, 1);
    }
  });

  test('a join with a duplicate display name is rejected', () async {
    final host = HostServer(hostDisplayName: 'Mumu');
    final port = await host.start();
    addTearDown(host.stop);

    final a = GameClient();
    addTearDown(a.close);
    await a.connectToLobby('127.0.0.1', port, 'Mumu');
    await _waitUntil(() => host.roster.length == 1);

    final b = GameClient();
    addTearDown(b.close);
    final rejection = b.joinRejected.first;
    await b.connectToLobby('127.0.0.1', port, 'Mumu');

    expect(await rejection, contains('already taken'));
    expect(host.roster.length, 1);
  });

  test('startGame throws below minPlayers', () async {
    final host = HostServer(hostDisplayName: 'Mumu');
    final port = await host.start();
    addTearDown(host.stop);

    final a = GameClient();
    addTearDown(a.close);
    await a.connectToLobby('127.0.0.1', port, 'Mumu');
    await _waitUntil(() => host.roster.length == 1);

    expect(() => host.startGame(), throwsStateError);
  });

  test('a client disconnecting during the lobby phase is dropped, not held', () async {
    final host = HostServer(hostDisplayName: 'Mumu');
    final port = await host.start();
    addTearDown(host.stop);

    final a = GameClient();
    addTearDown(a.close);
    await a.connectToLobby('127.0.0.1', port, 'Mumu');
    final b = GameClient();
    await b.connectToLobby('127.0.0.1', port, 'Zoe');
    await _waitUntil(() => host.roster.length == 2);

    await b.close();
    await _waitUntil(() => host.roster.length == 1);
    expect(host.roster.single.displayName, 'Mumu');
  });

  test(
    'whenStarted still completes for a client that checks it after the '
    'host has already started (broadcast-race regression)',
    () async {
      final host = HostServer(hostDisplayName: 'Mumu');
      final port = await host.start();
      addTearDown(host.stop);

      final a = GameClient();
      addTearDown(a.close);
      await a.connectToLobby('127.0.0.1', port, 'Mumu');
      final b = GameClient();
      addTearDown(b.close);
      await b.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);

      // Start the game, then wait for the LobbyStartedMessage to have been
      // fully received and marked (hasStarted) - simulating a UI that only
      // gets around to awaiting the transition after the event already
      // arrived. whenStarted must still complete rather than hang.
      host.startGame(seed: 1);
      await _waitUntil(() => b.hasStarted);

      // The event is long gone from the broadcast stream by now; awaiting
      // whenStarted here would hang forever if it relied on lobbyStarted.first.
      await b.whenStarted.timeout(const Duration(seconds: 1));
      expect(b.playerId, 'p1');
    },
  );
}
