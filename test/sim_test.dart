import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/game/sim.dart';
import 'package:pen_fight/screens/battle.dart';

Sim fresh() => Sim.duel(width: kTableW, height: kTableH);

void main() {
  test('identical inputs settle to identical state (netcode rests on this)',
      () {
    final a = fresh()
      ..applyFlick(0, const Vec2(0.12, -1), 0.83)
      ..settle();
    final b = fresh()
      ..applyFlick(0, const Vec2(0.12, -1), 0.83)
      ..settle();

    expect(a.snapshot().toString(), b.snapshot().toString());
  });

  test('a hard flick actually reaches and damages the opponent', () {
    final s = fresh();
    final inkBefore = s.seat(1)!.ink;
    final aim = s.seat(1)!.pos - s.seat(0)!.pos;
    final res = (s..applyFlick(0, aim, 0.85)).settle();

    expect(res.hits, contains(1), reason: 'seat 1 should have been struck');
    expect(s.seat(1)!.ink, lessThan(inkBefore));
  });

  test('a pen pushed past the edge is killed regardless of ink', () {
    final s = fresh();
    final p = s.seat(1)!;
    p.ink = 100;
    p.pos = Vec2(s.width * 0.5, 4);
    p.vel = const Vec2(0, -400);
    s.settle();

    expect(p.alive, isFalse);
    expect(p.ink, 100, reason: 'off-table is a KO, not ink damage');
  });

  test('settle always terminates', () {
    final s = fresh()..applyFlick(0, const Vec2(0.4, -1), 1.0);
    final res = s.settle();
    expect(res.ticks, lessThan(kMaxTicks));
    expect(s.pens.every((p) => !p.alive || p.resting), isTrue);
  });

  test('snapshot survives a round trip', () {
    final s = fresh()..applyFlick(0, const Vec2(0.3, -1), 0.7);
    s.settle();
    final snap = s.snapshot();

    final peer = fresh()..restore(snap);
    expect(peer.snapshot().toString(), snap.toString());
  });

  test('match ends when one pen is left', () {
    final s = fresh();
    s.seat(1)!.alive = false;
    expect(s.isOver, isTrue);
    expect(s.winnerSeat, 0);
  });
}
