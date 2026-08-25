import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/game/ai.dart';
import 'package:pen_fight/game/sim.dart';
import 'package:pen_fight/screens/battle.dart';

/// Plays a whole match: the bot on seat 1, a "decent human" on seat 0.
/// Returns true when the human wins.
bool _playMatch(Difficulty d, int seed) {
  final rng = math.Random(seed);
  final sim = Sim.duel(width: kTableW, height: kTableH);
  final bot = PenAi(d, seed: seed);

  for (var turn = 0; turn < 40; turn++) {
    final humanTurn = turn.isEven;

    if (humanTurn) {
      final me = sim.seat(0), foe = sim.seat(1);
      if (me == null || !me.alive || foe == null || !foe.alive) break;

      // A competent-but-imperfect player: aims at the opponent with a few
      // degrees of error and a sensible power.
      final to = foe.pos - me.pos;
      final angle = math.atan2(to.y, to.x) + (rng.nextDouble() - 0.5) * 0.22;
      final power = 0.62 + rng.nextDouble() * 0.28;
      sim.applyFlick(
          0, Vec2(math.cos(angle), math.sin(angle)), power, grab: me.pos);
    } else {
      final shot = bot.chooseShot(sim, 1);
      if (shot == null) break;
      sim.applyFlick(1, shot.direction, shot.power, grab: shot.grab);
    }

    sim.settle();
    if (sim.isOver) break;
  }

  return sim.winnerSeat == 0;
}

double _humanWinRate(Difficulty d, {int matches = 120}) {
  var wins = 0;
  for (var i = 0; i < matches; i++) {
    if (_playMatch(d, i * 7919 + d.index)) wins++;
  }
  return wins / matches;
}

void main() {
  test('the bot produces a legal, purposeful shot', () {
    final sim = Sim.duel(width: kTableW, height: kTableH);
    final shot = PenAi(Difficulty.hard, seed: 1).chooseShot(sim, 1);

    expect(shot, isNotNull);
    expect(shot!.power, inInclusiveRange(0.1, 1.0));
    expect(shot.direction.length, closeTo(1.0, 0.001),
        reason: 'direction should be a unit vector');

    // The grab must be on the bot's own pen, or the physics is wrong.
    final me = sim.seat(1)!;
    final (s1, s2) = me.segment;
    final (onPen, _) =
        closestPointsBetweenSegments(s1, s2, shot.grab, shot.grab);
    expect((shot.grab - onPen).length, lessThan(1.0));
  });

  test('the bot declines to play a dead pen', () {
    final sim = Sim.duel(width: kTableW, height: kTableH);
    sim.seat(1)!.alive = false;
    expect(PenAi(Difficulty.brutal, seed: 1).chooseShot(sim, 1), isNull);
  });

  test('the same seed produces the same shot', () {
    // Determinism matters: a replayed match must play out identically.
    final a = PenAi(Difficulty.hard, seed: 42)
        .chooseShot(Sim.duel(width: kTableW, height: kTableH), 1)!;
    final b = PenAi(Difficulty.hard, seed: 42)
        .chooseShot(Sim.duel(width: kTableW, height: kTableH), 1)!;

    expect(a.power, b.power);
    expect(a.direction.x, b.direction.x);
    expect(a.direction.y, b.direction.y);
  });

  test('difficulty is ordered: easy is beatable, ruthless is not', () {
    final easy = _humanWinRate(Difficulty.easy);
    final hard = _humanWinRate(Difficulty.hard);
    final brutal = _humanWinRate(Difficulty.brutal);

    // ignore: avoid_print
    print('human win rate — easy: ${(easy * 100).toStringAsFixed(0)}%  '
        'hard: ${(hard * 100).toStringAsFixed(0)}%  '
        'ruthless: ${(brutal * 100).toStringAsFixed(0)}%');

    expect(easy, greaterThan(hard),
        reason: 'easy must be easier than hard');
    expect(hard, greaterThan(brutal),
        reason: 'hard must be easier than ruthless');
  });

  test('easy gives a real chance of winning', () {
    expect(_humanWinRate(Difficulty.easy), greaterThan(0.35));
  });

  test('ruthless leaves roughly a 10% crack', () {
    final rate = _humanWinRate(Difficulty.brutal, matches: 300);
    // ignore: avoid_print
    print('ruthless over 300 matches: ${(rate * 100).toStringAsFixed(1)}%');
    // Tuned deliberately: ruthless should feel nearly unbeatable while still
    // being winnable often enough to be worth attempting. The band is wide
    // enough that ordinary sampling noise will not make this flaky.
    expect(rate, inInclusiveRange(0.05, 0.16),
        reason: 'ruthless should win about 90% of the time, not all of it');
  });
}
