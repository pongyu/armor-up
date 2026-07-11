import 'dart:convert';
import 'dart:io';

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
}

Future<void> _waitUntil(bool Function() predicate) async {
  while (!predicate()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

HostServer _buildHost({
  Duration? defenseResponseTimeout = const Duration(milliseconds: 150),
  Duration reconnectGracePeriod = const Duration(seconds: 5),
}) =>
    HostServer(
      hostDisplayName: 'Mumu',
      reconnectGracePeriod: reconnectGracePeriod,
      defenseResponseTimeout: defenseResponseTimeout,
    );

void main() {
  group('defense-response timeout', () {
    test(
      'a timer firing with no response lands the attack via a system decline',
      () async {
        final host = _buildHost();
        final port = await host.start();
        addTearDown(host.stop);

        final p0Client = GameClient();
        addTearDown(p0Client.close);
        await p0Client.connectToLobby('127.0.0.1', port, 'Mumu');
        final p1Client = GameClient();
        addTearDown(p1Client.close);
        await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');

        await _waitUntil(() => host.roster.length == 2);

        final p0Started = p0Client.lobbyStarted.first;
        final p1Started = p1Client.lobbyStarted.first;
        // seed 1 deals p0: [strife, prayer, confusion, deception,
        // wilderness_season] and p1: [fellowship, renewal, fiery_dart,
        // discouragement, prayer] - p0 plays strife (an attack, targets
        // shoes) at p1, who holds a Prayer, opening a defense window.
        host.startGame(seed: 1);
        await p0Started;
        await p1Started;

        final p1States = _StateSpy(p1Client);

        p0Client.dispatch(const DrawCard(playerId: 'p0'));
        await _waitUntil(() => host.state?.hasDrawnThisTurn == true);

        final strifeId =
            host.state!.playerById('p0').hand.firstWhere((c) => c.defId == 'strife').instanceId;
        p0Client.dispatch(
          PlayCard(playerId: 'p0', cardInstanceId: strifeId, targetPlayerId: 'p1'),
        );
        await _waitUntil(() => host.state?.pendingInterrupt != null);
        expect(host.state!.pendingInterrupt!.defenderId, 'p1');

        // p1 never responds. After the (short, test-only) timeout, the
        // host should apply a system decline on p1's behalf and the
        // attack should land.
        await _waitUntil(() => host.state?.pendingInterrupt == null);
        expect(
          host.state!.players.firstWhere((p) => p.id == 'p1').armorOf(ArmorType.shoes).condition,
          ArmorCondition.weakened,
        );
        expect(host.state!.eventLog.whereType<DefenseTimedOut>(), hasLength(1));
        expect(host.state!.eventLog.whereType<DefenseTimedOut>().single.playerId, 'p1');

        // The defending client's own broadcast stream converges on the
        // same result the host holds authoritatively. Matched on the
        // resolved armor condition (not just "no pending interrupt",
        // which is also true of every state before the attack was even
        // played) so this picks out the post-timeout broadcast
        // specifically.
        bool isResolved(FilteredGameState s) =>
            s.pendingInterrupt == null &&
            s.players
                    .firstWhere((p) => p.id == 'p1')
                    .armor
                    .firstWhere((a) => a.type == ArmorType.shoes)
                    .condition ==
                ArmorCondition.weakened;
        await _waitUntil(() => p1States.received.any(isResolved));
      },
    );

    test('the defender responding before the deadline cancels the timer', () async {
      final host = _buildHost();
      final port = await host.start();
      addTearDown(host.stop);

      final p0Client = GameClient();
      addTearDown(p0Client.close);
      await p0Client.connectToLobby('127.0.0.1', port, 'Mumu');
      final p1Client = GameClient();
      addTearDown(p1Client.close);
      await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);

      final p0Started = p0Client.lobbyStarted.first;
      final p1Started = p1Client.lobbyStarted.first;
      host.startGame(seed: 1);
      await p0Started;
      await p1Started;

      p0Client.dispatch(const DrawCard(playerId: 'p0'));
      await _waitUntil(() => host.state?.hasDrawnThisTurn == true);
      final strifeId =
          host.state!.playerById('p0').hand.firstWhere((c) => c.defId == 'strife').instanceId;
      p0Client.dispatch(PlayCard(playerId: 'p0', cardInstanceId: strifeId, targetPlayerId: 'p1'));
      await _waitUntil(() => host.state?.pendingInterrupt != null);

      final prayerId =
          host.state!.playerById('p1').hand.firstWhere((c) => c.defId == 'prayer').instanceId;
      p1Client.dispatch(DeclareDefense(playerId: 'p1', cardInstanceId: prayerId));
      await _waitUntil(() => host.state?.pendingInterrupt == null);

      // Wait past where the timeout would have fired, then confirm no
      // system decline was ever logged - the block (Prayer) is what
      // resolved this, not a timeout.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.state!.eventLog.whereType<DefenseTimedOut>(), isEmpty);
      expect(host.state!.eventLog.whereType<AttackBlocked>(), hasLength(1));
      expect(
        host.state!.players.firstWhere((p) => p.id == 'p1').armorOf(ArmorType.shoes).condition,
        ArmorCondition.strong,
      );
    });

    test('a Fellowship helper chain restarts the timer per helper', () async {
      // seed 2 deals p0: [armor_bearer, deception, doubt, fellowship,
      // fiery_dart], p1: [pride, goliaths_taunt, renewal, fellowship,
      // road_to_damascus] - a 3-player game so there's a genuine helper
      // distinct from the attacker/defender.
      final host = _buildHost();
      final port = await host.start();
      addTearDown(host.stop);

      final p0Client = GameClient();
      addTearDown(p0Client.close);
      await p0Client.connectToLobby('127.0.0.1', port, 'Mumu');
      final p1Client = GameClient();
      addTearDown(p1Client.close);
      await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');
      final p2Client = GameClient();
      addTearDown(p2Client.close);
      await p2Client.connectToLobby('127.0.0.1', port, 'Sam');
      await _waitUntil(() => host.roster.length == 3);

      final started = [
        p0Client.lobbyStarted.first,
        p1Client.lobbyStarted.first,
        p2Client.lobbyStarted.first,
      ];
      host.startGame(seed: 2);
      await Future.wait(started);

      p0Client.dispatch(const DrawCard(playerId: 'p0'));
      await _waitUntil(() => host.state?.hasDrawnThisTurn == true);
      final attackCard = host.state!
          .playerById('p0')
          .hand
          .firstWhere((c) => cardDefById(c.defId).type == CardType.attack);
      final attackDef = cardDefById(attackCard.defId);
      p0Client.dispatch(
        PlayCard(
          playerId: 'p0',
          cardInstanceId: attackCard.instanceId,
          targetPlayerId: 'p1',
          targetArmor: attackDef.fixedTarget ?? ArmorType.helmet,
        ),
      );
      await _waitUntil(() => host.state?.pendingInterrupt != null);
      final defenderId = host.state!.pendingInterrupt!.defenderId;

      final fellowshipId = host.state!
          .playerById(defenderId)
          .hand
          .where((c) => c.defId == 'fellowship')
          .map((c) => c.instanceId)
          .firstOrNull;
      // Only proceed with the Fellowship-specific assertions if this
      // seed's deal actually gave the defender a Fellowship card (it
      // does for seed 2 with p1 as defender, per the hands listed above).
      expect(fellowshipId, isNotNull, reason: 'expected the defender to hold Fellowship for seed 2');

      final defenderClient = defenderId == 'p1' ? p1Client : p2Client;
      defenderClient.dispatch(
        DeclareDefense(playerId: defenderId, cardInstanceId: fellowshipId!),
      );
      await _waitUntil(() => host.state?.pendingInterrupt?.fellowshipRequested == true);

      // Nobody helps: the timer should fire for the helper first (logging
      // a helper DefenseTimedOut), then fall through to the defender's
      // own window and time out again, landing the attack.
      await _waitUntil(() => host.state?.pendingInterrupt == null);
      final timeouts = host.state!.eventLog.whereType<DefenseTimedOut>().toList();
      expect(timeouts, isNotEmpty);
      expect(timeouts.any((e) => e.wasHelper), isTrue);
    });

    test('a disconnected current actor suppresses the timer until they reconnect', () async {
      final host = _buildHost();
      final port = await host.start();
      addTearDown(host.stop);

      final p0Client = GameClient();
      addTearDown(p0Client.close);
      await p0Client.connectToLobby('127.0.0.1', port, 'Mumu');
      final p1Client = GameClient();
      await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);

      final p0Started = p0Client.lobbyStarted.first;
      final p1Started = p1Client.lobbyStarted.first;
      host.startGame(seed: 1);
      await p0Started;
      await p1Started;
      final p1PlayerId = p1Client.playerId!;
      final p1Token = p1Client.sessionToken!;

      p0Client.dispatch(const DrawCard(playerId: 'p0'));
      await _waitUntil(() => host.state?.hasDrawnThisTurn == true);
      final strifeId =
          host.state!.playerById('p0').hand.firstWhere((c) => c.defId == 'strife').instanceId;
      p0Client.dispatch(PlayCard(playerId: 'p0', cardInstanceId: strifeId, targetPlayerId: 'p1'));
      await _waitUntil(() => host.state?.pendingInterrupt != null);

      // p1 (the defender) disconnects before responding.
      await p1Client.close();
      await _waitUntil(
        () => !host.roster.any((p) => p.playerId == p1PlayerId) || true,
      );
      // Give the host a moment to process the disconnect (onDone callback).
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Wait well past what the defense-response timeout would have
      // been: since the defender is disconnected, the reconnect grace
      // period (5s) governs instead, and no system decline should fire.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(host.state!.pendingInterrupt, isNotNull);
      expect(host.state!.eventLog.whereType<DefenseTimedOut>(), isEmpty);

      // Reconnecting restarts the deadline fresh; without responding
      // again, it should now fire and resolve the attack.
      final reconnected = GameClient();
      addTearDown(reconnected.close);
      await reconnected.reconnect('127.0.0.1', port, p1PlayerId, p1Token);
      await _waitUntil(() => host.state?.pendingInterrupt == null);
      expect(host.state!.eventLog.whereType<DefenseTimedOut>(), hasLength(1));
    });

    test('a group-discard timeout discards exactly one random card from each stalled player', () async {
      final host = _buildHost();
      final port = await host.start();
      addTearDown(host.stop);

      final p0Client = GameClient();
      addTearDown(p0Client.close);
      await p0Client.connectToLobby('127.0.0.1', port, 'Mumu');
      final p1Client = GameClient();
      addTearDown(p1Client.close);
      await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);

      final p0Started = p0Client.lobbyStarted.first;
      final p1Started = p1Client.lobbyStarted.first;
      // seed 1: p0 holds 'wilderness_season'.
      host.startGame(seed: 1);
      await p0Started;
      await p1Started;

      p0Client.dispatch(const DrawCard(playerId: 'p0'));
      await _waitUntil(() => host.state?.hasDrawnThisTurn == true);
      final wildernessId = host.state!
          .playerById('p0')
          .hand
          .firstWhere((c) => c.defId == 'wilderness_season')
          .instanceId;
      p0Client.dispatch(PlayCard(playerId: 'p0', cardInstanceId: wildernessId));
      await _waitUntil(() => host.state?.pendingGroupDiscard != null);

      final owed = {...host.state!.pendingGroupDiscard!.owedPlayerIds};
      final beforeHandSizes = {for (final id in owed) id: host.state!.playerById(id).hand.length};

      // Nobody discards: the timer should fire once per stalled player,
      // each time discarding exactly one random card, until the
      // obligation is fully cleared.
      await _waitUntil(() => host.state?.pendingGroupDiscard == null);

      for (final id in owed) {
        expect(host.state!.playerById(id).hand.length, beforeHandSizes[id]! - 1);
      }
    });

    test('a null defenseResponseTimeout disables the mechanism entirely', () async {
      final host = _buildHost(defenseResponseTimeout: null);
      final port = await host.start();
      addTearDown(host.stop);

      final p0Client = GameClient();
      addTearDown(p0Client.close);
      await p0Client.connectToLobby('127.0.0.1', port, 'Mumu');
      final p1Client = GameClient();
      addTearDown(p1Client.close);
      await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');
      await _waitUntil(() => host.roster.length == 2);

      final p0Started = p0Client.lobbyStarted.first;
      final p1Started = p1Client.lobbyStarted.first;
      host.startGame(seed: 1);
      await p0Started;
      await p1Started;

      p0Client.dispatch(const DrawCard(playerId: 'p0'));
      await _waitUntil(() => host.state?.hasDrawnThisTurn == true);
      final strifeId =
          host.state!.playerById('p0').hand.firstWhere((c) => c.defId == 'strife').instanceId;
      p0Client.dispatch(PlayCard(playerId: 'p0', cardInstanceId: strifeId, targetPlayerId: 'p1'));
      await _waitUntil(() => host.state?.pendingInterrupt != null);

      // Wait well past what a default timeout would have been; with the
      // mechanism disabled, the interrupt must still be pending.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(host.state!.pendingInterrupt, isNotNull);
      expect(host.state!.eventLog.whereType<DefenseTimedOut>(), isEmpty);
    });

    test(
      'the raw StateMessage envelope carries responseDeadlineEpochMs while an interrupt is pending, and omits it otherwise',
      () async {
        final host = _buildHost();
        final port = await host.start();
        addTearDown(host.stop);

        // Connect a raw WebSocket (rather than GameClient, which only
        // exposes the already-decoded FilteredGameState) so the envelope
        // field itself - not just its downstream effect - can be
        // inspected directly.
        final rawSocket = await WebSocket.connect('ws://127.0.0.1:$port');
        addTearDown(rawSocket.close);
        final rawMessages = <Map<String, dynamic>>[];
        rawSocket.listen((raw) => rawMessages.add(jsonDecode(raw as String) as Map<String, dynamic>));
        rawSocket.add(jsonEncode(const JoinLobbyMessage(displayName: 'Mumu').toJson()));
        await _waitUntil(() => host.roster.length == 1);

        final p1Client = GameClient();
        addTearDown(p1Client.close);
        await p1Client.connectToLobby('127.0.0.1', port, 'Zoe');
        await _waitUntil(() => host.roster.length == 2);

        final p1Started = p1Client.lobbyStarted.first;
        host.startGame(seed: 1);
        await p1Started;
        await _waitUntil(() => rawMessages.any((m) => m['type'] == 'state'));

        // No pending interrupt yet: the initial broadcast(s) must omit
        // the deadline field entirely.
        final initialStateMessages = rawMessages.where((m) => m['type'] == 'state');
        expect(
          initialStateMessages.every((m) => !m.containsKey('responseDeadlineEpochMs')),
          isTrue,
        );

        // p0 is the raw socket's assigned id (first to join, per
        // HostServer's join-order id assignment) and is the active
        // player, so its actions are dispatched over the raw socket
        // itself rather than through a GameClient.
        rawSocket.add(
          jsonEncode(
            const ActionMessage(DrawCard(playerId: 'p0')).toJson(),
          ),
        );
        await _waitUntil(() => host.state?.hasDrawnThisTurn == true);

        final strifeId =
            host.state!.playerById('p0').hand.firstWhere((c) => c.defId == 'strife').instanceId;
        rawSocket.add(
          jsonEncode(
            ActionMessage(
              PlayCard(playerId: 'p0', cardInstanceId: strifeId, targetPlayerId: 'p1'),
            ).toJson(),
          ),
        );
        await _waitUntil(() => host.state?.pendingInterrupt != null);
        await _waitUntil(
          () => rawMessages.any(
            (m) => m['type'] == 'state' && m.containsKey('responseDeadlineEpochMs'),
          ),
        );

        final withDeadline = rawMessages.lastWhere(
          (m) => m['type'] == 'state' && m.containsKey('responseDeadlineEpochMs'),
        );
        final deadline = withDeadline['responseDeadlineEpochMs'] as int;
        expect(deadline, greaterThan(DateTime.now().millisecondsSinceEpoch));

        // Once the timeout fires and the interrupt resolves, subsequent
        // broadcasts must omit the field again.
        await _waitUntil(() => host.state?.pendingInterrupt == null);
        await _waitUntil(() {
          final latestState =
              rawMessages.lastWhere((m) => m['type'] == 'state', orElse: () => const {});
          return latestState.isNotEmpty && !latestState.containsKey('responseDeadlineEpochMs');
        });
      },
    );
  });
}
