import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/game/sim.dart';
import 'package:pen_fight/screens/battle.dart';

Sim table(int n) =>
    Sim.table(width: kTableW, height: kTableH, players: n);

void main() {
  test('tables deal the requested number of pens', () {
    for (var n = 2; n <= kMaxPlayers; n++) {
      final s = table(n);
      expect(s.pens.length, n);
      expect(s.living.length, n);
      // Seats are 0..n-1 with no gaps or duplicates.
      expect(s.pens.map((p) => p.seat).toSet(), {for (var i = 0; i < n; i++) i});
    }
  });

  test('player count is clamped to something playable', () {
    expect(table(1).pens.length, 2, reason: 'a solo table is not a game');
    expect(table(9).pens.length, kMaxPlayers);
  });

  test('nobody starts off the table or in the danger band', () {
    for (var n = 2; n <= kMaxPlayers; n++) {
      for (final p in table(n).pens) {
        expect(p.pos.x, inInclusiveRange(kDangerBand, kTableW - kDangerBand),
            reason: '$n-player seat ${p.seat} starts too near an edge');
        expect(p.pos.y, inInclusiveRange(kDangerBand, kTableH - kDangerBand),
            reason: '$n-player seat ${p.seat} starts too near an edge');
      }
    }
  });

  test('nobody starts already touching someone else', () {
    for (var n = 2; n <= kMaxPlayers; n++) {
      final s = table(n);
      for (var i = 0; i < s.pens.length; i++) {
        for (var j = i + 1; j < s.pens.length; j++) {
          final (a1, a2) = s.pens[i].segment;
          final (b1, b2) = s.pens[j].segment;
          final (ca, cb) = closestPointsBetweenSegments(a1, a2, b1, b2);
          expect((cb - ca).length, greaterThan(kPenRadius * 2),
              reason: '$n-player: seats $i and $j overlap at the start');
        }
      }
    }
  });

  test('the opening layout is identical on every client', () {
    for (var n = 2; n <= kMaxPlayers; n++) {
      expect(table(n).snapshot().toString(), table(n).snapshot().toString());
    }
  });

  test('turn order rotates through everyone', () {
    final s = table(5);
    var turn = 0;
    final visited = <int>[];
    for (var i = 0; i < 5; i++) {
      visited.add(turn);
      turn = s.nextLivingSeat(turn);
    }
    expect(visited, [0, 1, 2, 3, 4]);
    expect(s.nextLivingSeat(4), 0, reason: 'and wraps around');
  });

  test('turn order skips players who are out', () {
    final s = table(5);
    s.seat(1)!.alive = false;
    s.seat(2)!.alive = false;

    expect(s.nextLivingSeat(0), 3, reason: 'hops over both eliminated seats');
    expect(s.nextLivingSeat(3), 4);
    expect(s.nextLivingSeat(4), 0);
  });

  test('a lone survivor keeps the turn rather than looping forever', () {
    final s = table(5);
    for (final p in s.pens) {
      if (p.seat != 2) p.alive = false;
    }
    expect(s.nextLivingSeat(2), 2);
    expect(s.isOver, isTrue);
    expect(s.winnerSeat, 2);
  });

  test('a 5-player match is not over until one pen remains', () {
    final s = table(5);
    expect(s.isOver, isFalse);
    for (final seat in [0, 1, 2]) {
      s.seat(seat)!.alive = false;
      expect(s.isOver, isFalse, reason: 'two pens still standing');
    }
    s.seat(3)!.alive = false;
    expect(s.isOver, isTrue);
    expect(s.winnerSeat, 4);
  });
}
