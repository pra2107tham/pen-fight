import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/game/sim.dart';
import 'package:pen_fight/net/room.dart';

void main() {
  test('room codes avoid characters people misread', () {
    // O/0 and I/1 are the classic misreads when someone types a code from a
    // photo or reads it aloud across a desk.
    for (var i = 0; i < 200; i++) {
      final code = Room.newCode();
      expect(code.length, 4);
      expect(code, matches(RegExp(r'^[A-Z2-9]{4}$')));
      expect(code, isNot(contains('O')));
      expect(code, isNot(contains('I')));
      expect(code, isNot(contains('0')));
      expect(code, isNot(contains('1')));
    }
  });

  test('codes are drawn from a wide enough space to not collide often', () {
    final seen = <String>{};
    for (var i = 0; i < 500; i++) {
      seen.add(Room.newCode());
    }
    // 32^4 ≈ 1M combinations; 500 draws should almost never repeat.
    expect(seen.length, greaterThan(495));
  });

  test('every join failure has a message worth showing a player', () {
    for (final e in JoinError.values) {
      expect(e.message, isNotEmpty);
      // No enum names or exception text leaking into the UI.
      expect(e.message, isNot(contains('JoinError')));
      expect(e.message, isNot(contains('Exception')));
    }
  });

  test('a room starts out connecting, not silently live', () {
    final r = Room(code: 'TEST', isHost: true);
    addTearDown(r.dispose);

    expect(r.link, LinkState.connecting);
    expect(r.usable, isFalse,
        reason: 'play must not be allowed before the channel is up');
    expect(r.peerForfeited, isFalse);
    expect(r.peerMissingFor, isNull);
  });

  test('the host takes seat 0 and guests take later seats', () {
    final host = Room(code: 'TEST', isHost: true);
    final guest = Room(code: 'TEST', isHost: false);
    addTearDown(host.dispose);
    addTearDown(guest.dispose);

    expect(host.mySeat, 0);
    expect(guest.mySeat, 1);
  });

  test('a guest can be seated anywhere at a bigger table', () {
    for (var seat = 1; seat < kMaxPlayers; seat++) {
      final r = Room(code: 'TEST', isHost: false, capacity: 5, seat: seat);
      addTearDown(r.dispose);
      expect(r.mySeat, seat);
    }
  });

  test('a table is only full once every seat is taken', () {
    final r = Room(code: 'TEST', isHost: true, capacity: 5);
    addTearDown(r.dispose);
    expect(r.capacity, 5);
    expect(r.isFull, isFalse, reason: 'nobody has joined yet');
  });

  test('names are supplied for every seat, even empty ones', () {
    final r = Room(code: 'TEST', isHost: true, capacity: 5);
    addTearDown(r.dispose);

    final names = r.playerNames;
    expect(names.length, 5);
    expect(names.every((n) => n.isNotEmpty), isTrue,
        reason: 'an empty seat still needs a label on the HUD');
  });

  test('a supplied player id is kept so a refresh rejoins the same seat', () {
    final first = Room(code: 'TEST', isHost: false, id: 'stable-id');
    final afterReload = Room(code: 'TEST', isHost: false, id: 'stable-id');
    addTearDown(first.dispose);
    addTearDown(afterReload.dispose);

    expect(first.myId, 'stable-id');
    expect(afterReload.myId, first.myId,
        reason: 'the same device must look like the same player');
  });

  test('rooms without an explicit id still get unique ones', () {
    final a = Room(code: 'TEST', isHost: true);
    final b = Room(code: 'TEST', isHost: true);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(a.myId, isNot(b.myId));
  });

  test('an empty room reports no peer present', () {
    final r = Room(code: 'TEST', isHost: true);
    addTearDown(r.dispose);
    expect(r.peerPresent, isFalse);
    expect(r.isFull, isFalse);
  });

  test('the grace period is long enough to survive a brief blip', () {
    // A wifi hiccup or a backgrounded tab should not cost you the match.
    expect(kPeerGrace.inSeconds, greaterThanOrEqualTo(15));
    expect(kPeerGrace.inSeconds, lessThanOrEqualTo(120));
  });

  test('room lifetime outlasts a plausible match', () {
    expect(kRoomTtl.inMinutes, greaterThanOrEqualTo(30));
  });
}
