import 'dart:math' as math;

import 'sim.dart';

/// How hard the computer plays.
enum Difficulty { easy, hard, brutal }

extension DifficultyInfo on Difficulty {
  String get label => switch (this) {
        Difficulty.easy => 'EASY',
        Difficulty.hard => 'HARD',
        Difficulty.brutal => 'RUTHLESS',
      };

  String get blurb => switch (this) {
        Difficulty.easy => 'Soft flicks, loose aim. Warms up your thumb.',
        Difficulty.hard => 'Reads the angle. Goes for the edge.',
        Difficulty.brutal => 'Searches every shot. You will not win.',
      };

  String get stars => switch (this) {
        Difficulty.easy => '1★',
        Difficulty.hard => '2★',
        Difficulty.brutal => '3★',
      };

  /// How many candidate shots to simulate before picking. More search means
  /// better play — this is the main lever between the tiers.
  int get samples => switch (this) {
        Difficulty.easy => 6,
        Difficulty.hard => 120,
        Difficulty.brutal => 700,
      };

  /// Whether to also simulate the opponent's best reply. Looking a ply ahead
  /// is what separates "aims well" from "you cannot win": the bot stops
  /// playing shots that leave itself set up to be knocked off.
  bool get searchesReplies => this == Difficulty.brutal;

  /// How many replies to try when looking ahead.
  int get replySamples => 26;

  /// How many of the best candidate shots get a ply of lookahead.
  ///
  /// Looking ahead costs [replySamples] full settles, so running it on every
  /// candidate meant 700 x 27 settles for one Ruthless turn — seconds of a
  /// frozen tab on the web. Shots outside the leading group lost on their own
  /// merits and cannot be rescued by a lookahead bonus, since the reply term
  /// only ever subtracts. Spending the lookahead on the shortlist instead
  /// costs a fraction as much and decides between the same shots.
  int get finalists => searchesReplies ? 24 : 0;

  /// Random error added to the chosen aim, in radians. The bot is made
  /// beatable by making it miss, not by hiding information from it.
  double get aimJitter => switch (this) {
        Difficulty.easy => 0.42,
        Difficulty.hard => 0.06,
        Difficulty.brutal => 0.05,
      };

  /// Error applied to power, as a fraction.
  double get powerJitter => switch (this) {
        Difficulty.easy => 0.35,
        Difficulty.hard => 0.05,
        Difficulty.brutal => 0.0,
      };

  /// Chance the bot deliberately fluffs an otherwise good shot.
  ///
  /// Ruthless keeps a deliberate crack: a perfect opponent is a wall, not a
  /// game. These values were swept against simulated matches to land the
  /// human win rate near 10% — see test/ai_test.dart, which asserts the band.
  double get blunderChance => switch (this) {
        Difficulty.easy => 0.45,
        Difficulty.hard => 0.05,
        Difficulty.brutal => 0.15,
      };
}

/// A shot the computer intends to play.
class AiShot {
  final Vec2 direction;
  final double power;
  final Vec2 grab;
  final double score;

  const AiShot({
    required this.direction,
    required this.power,
    required this.grab,
    required this.score,
  });
}

/// Picks a shot by simulating candidates against the real physics.
///
/// Because [Sim] is deterministic and cheap to copy, the bot can simply try
/// many shots and keep the best-scoring one. Difficulty is then a matter of
/// how many it tries and how much noise is added afterwards — no separate
/// "AI physics" that could disagree with the real game.
class PenAi {
  final Difficulty difficulty;
  final math.Random _rng;

  PenAi(this.difficulty, {int? seed}) : _rng = math.Random(seed);

  /// Choose a shot for [seat]. Returns null if that pen cannot play.
  ///
  /// Two phases: score every candidate on how the shot itself plays out, then
  /// spend the expensive one-ply lookahead only on the shortlist that could
  /// still win. See [DifficultyInfo.finalists].
  AiShot? chooseShot(Sim sim, int seat) {
    final me = sim.seat(seat);
    if (me == null || !me.alive) return null;

    final opponents =
        sim.pens.where((p) => p.alive && p.seat != seat).toList();
    if (opponents.isEmpty) return null;

    final candidates = <AiShot>[];
    for (var i = 0; i < difficulty.samples; i++) {
      final candidate = _sample(sim, me, opponents, i);
      if (candidate != null) candidates.add(candidate);
    }
    if (candidates.isEmpty) return null;

    final shortlist = difficulty.finalists;
    if (shortlist == 0) {
      var best = candidates.first;
      for (final c in candidates) {
        if (c.score > best.score) best = c;
      }
      return _degrade(best, me);
    }

    // Strongest first, then look a ply ahead down the shortlist and keep
    // whichever survives its own best answer.
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final depth = math.min(shortlist, candidates.length);

    var best = candidates.first;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < depth; i++) {
      final c = candidates[i];
      // Replay the shot to get the position it leaves behind. Cheaper than
      // holding 700 settled boards in memory, and identical either way.
      final after = sim.copy()..applyFlick(seat, c.direction, c.power, grab: c.grab);
      after.settle();

      // A shot that wins the exchange but hands over an easy kill is not a
      // good shot.
      final score = after.isOver
          ? c.score
          : c.score - _bestReplyValue(after, seat) * 0.85;

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    return _degrade(best, me);
  }

  /// Build one candidate shot and score how it actually plays out.
  AiShot? _sample(Sim sim, Pen me, List<Pen> opponents, int index) {
    final target = opponents.first;
    final toTarget = target.pos - me.pos;
    final baseAngle = math.atan2(toTarget.y, toTarget.x);

    // The first sample is always the straight-at-them shot, so even a
    // one-sample bot plays something sensible. The rest fan out around it.
    final spread = index == 0 ? 0.0 : (_rng.nextDouble() - 0.5) * 1.5;
    final angle = baseAngle + spread;
    final dir = Vec2(math.cos(angle), math.sin(angle));

    final power = index == 0
        ? 0.78
        : 0.35 + _rng.nextDouble() * 0.65;

    // Vary where along the shaft it strikes — off-centre pulls curve.
    final (s1, s2) = me.segment;
    final t = index == 0 ? 0.5 : _rng.nextDouble();
    final grab = Vec2(
      s1.x + (s2.x - s1.x) * t,
      s1.y + (s2.y - s1.y) * t,
    );

    final trial = sim.copy()..applyFlick(me.seat, dir, power, grab: grab);
    final result = trial.settle();

    return AiShot(
      direction: dir,
      power: power,
      grab: grab,
      score: _score(trial, result, me.seat),
    );
  }

  /// The value of the opponent's best answer to this position, from their
  /// point of view. Used to avoid shots that leave us exposed.
  double _bestReplyValue(Sim after, int mySeat) {
    final foe = after.pens.firstWhere(
      (p) => p.alive && p.seat != mySeat,
      orElse: () => after.pens.first,
    );
    if (!foe.alive) return 0;

    final me = after.seat(mySeat);
    if (me == null || !me.alive) return 0;

    var best = 0.0;
    final toMe = me.pos - foe.pos;
    final baseAngle = math.atan2(toMe.y, toMe.x);

    for (var i = 0; i < difficulty.replySamples; i++) {
      final angle = baseAngle + (i == 0 ? 0.0 : (_rng.nextDouble() - .5) * .7);
      final power = 0.5 + _rng.nextDouble() * 0.5;
      final reply = after.copy()
        ..applyFlick(foe.seat, Vec2(math.cos(angle), math.sin(angle)), power,
            grab: foe.pos);
      final r = reply.settle();

      final meAfter = reply.seat(mySeat);
      if (meAfter == null) continue;

      var value = (100 - meAfter.ink) * 4;
      if (!meAfter.alive) value += 1000;
      if (r.hits.contains(mySeat)) value += 60;
      if (value > best) best = value;
    }
    return best;
  }

  /// Higher is better for [seat].
  double _score(Sim after, FlickResult result, int seat) {
    final me = after.seat(seat);
    if (me == null) return -1e9;

    // Suiciding is always the worst outcome.
    if (!me.alive) return -1e6;

    var score = 0.0;

    for (final p in after.pens) {
      if (p.seat == seat) continue;
      // Knocking someone off the table is the win condition.
      if (!p.alive) score += 1000;
      // Otherwise, ink taken off them is the currency.
      score += (100 - p.ink) * 4;

      // Reward leaving them near an edge, set up for the next shot.
      final edge = math.min(
        math.min(p.pos.x, after.width - p.pos.x),
        math.min(p.pos.y, after.height - p.pos.y),
      );
      score += math.max(0, 200 - edge) * 0.6;
    }

    // Staying safe matters: penalise parking our own pen near a drop.
    final myEdge = math.min(
      math.min(me.pos.x, after.width - me.pos.x),
      math.min(me.pos.y, after.height - me.pos.y),
    );
    score -= math.max(0, 200 - myEdge) * 0.9;
    score += me.ink * 1.5;

    // Landing a hit at all is worth something even if it did little.
    if (result.hits.isNotEmpty) score += 60;

    return score;
  }

  /// Apply difficulty noise. The search finds a good shot; this decides how
  /// faithfully the bot executes it.
  AiShot _degrade(AiShot shot, Pen me) {
    final blunder = _rng.nextDouble() < difficulty.blunderChance;

    final jitter = difficulty.aimJitter * (blunder ? 2.6 : 1.0);
    final angle = math.atan2(shot.direction.y, shot.direction.x) +
        (_rng.nextDouble() - 0.5) * 2 * jitter;

    var power = shot.power *
        (1 + (_rng.nextDouble() - 0.5) * 2 * difficulty.powerJitter);
    if (blunder) power *= 0.55; // a weak, short shot
    power = power.clamp(0.1, 1.0);

    return AiShot(
      direction: Vec2(math.cos(angle), math.sin(angle)),
      power: power,
      grab: shot.grab,
      score: shot.score,
    );
  }
}
