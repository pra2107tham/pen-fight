import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../game/ai.dart';
import '../game/sim.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/paper.dart';
import 'win.dart';

/// Logical table size. The sim runs in these units and the view scales to fit,
/// so both clients simulate identically regardless of screen size.
///
/// Sized so a pen spans roughly a sixth of the table, the way a real pen sits
/// on a real desk — pens start far apart and a flick has distance to cover.
const double kTableW = 820;
const double kTableH = 880;

/// Distance from the edge at which a pen reads as "about to fall off".
const double kDangerBand = 70;

/// How close to your pen a drag must start to grab it (table units).
const double kGrabRadius = 70;

/// Pull distance (table units) for a 100% shot. Larger = less sensitive,
/// so a small twitch no longer launches a full-power flick.
const double kPullRange = 420;

/// Anchors the table rect so tests can map table coords to the screen.
const Key kTableKey = Key('pf-table');

/// Anchors the layer every pen is drawn on, so tests can find it.
const Key kPensKey = Key('pf-pens');

/// A pen close enough to an edge to read as "about to fall off".
bool penInDanger(Pen p) =>
    p.alive &&
    (p.pos.x < kDangerBand ||
        p.pos.x > kTableW - kDangerBand ||
        p.pos.y < kDangerBand ||
        p.pos.y > kTableH - kDangerBand);

/// Fields stored per pen per replay frame: x, y, angle, ink, alive, vx, vy.
const int _kReplayStride = 7;

class BattleScreen extends StatefulWidget {
  final Room? room; // null = local pass & play

  /// When set, every seat except 0 is played by the computer.
  final Difficulty? ai;

  /// One name per seat. Its length decides how many pens are on the table.
  final List<String> names;

  /// Hot-seat on one device: show a "pass the pen" screen between turns so
  /// the next player can pick it up without seeing the previous aim.
  final bool passAndPlay;

  const BattleScreen({
    super.key,
    this.room,
    this.ai,
    this.names = const ['YOU', 'RIVAL'],
    this.passAndPlay = false,
  });

  int get playerCount => names.length.clamp(2, kMaxPlayers);

  String nameFor(int seat) =>
      seat < names.length ? names[seat] : PF.seatNames[seat % 5];

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with SingleTickerProviderStateMixin {
  late Sim _sim;
  late final AnimationController _anim;

  int _turn = 0;
  bool _busy = false; // a flick is playing out; input locked
  Offset? _dragStart, _dragNow;

  /// Where along your own pen the shot will be struck, as 0..1 from one tip
  /// to the other. Chosen in stage one, then used as the grab point.
  double _contact = 0.5;

  /// Stage one = choosing the contact point, stage two = aiming the shot.
  bool _contactLocked = false;
  /// Where the drag actually caught the pen, clamped onto its spine. This is
  /// the single source of truth for both the physics and the aim overlay.
  Vec2? _grabOnPen;
  Vec2? _splatAt;
  Color _splatColor = PF.red;
  int _clock = 8;
  /// Whose turn it is once the current flick finishes playing out. Set when
  /// the flick is issued so both clients agree regardless of frame timing.
  int? _pendingTurn;
  PenAi? _bot;
  bool _botThinking = false;

  /// Hot-seat only: true while waiting for the next player to take the
  /// device, so they do not see the previous player's aim.
  bool _awaitingHandover = false;

  // Replay state: the flick is simulated up front and every tick recorded, so
  // playing it back is a lookup rather than a re-simulation.
  //
  // One flat buffer of doubles, allocated once and reused for every flick.
  // Held as JSON maps this cost thousands of map allocations to record a
  // single flick and five more copies on every frame of playback — the
  // heaviest source of garbage in the game.
  late final Float64List _replay;
  int _replayFrames = 0;

  /// Bumped once per replay frame and once per drag move. The pen layer and
  /// the aim overlay listen to it and repaint themselves, so a flick no
  /// longer rebuilds the whole screen sixty times a second.
  final ValueNotifier<int> _paint = ValueNotifier(0);

  /// Fingerprint of everything on screen that is not a pen — see
  /// [_boardSignature]. Only a change here needs a real rebuild.
  double _boardSig = 0;

  bool get _online => widget.room != null;
  bool get _vsComputer => _bot != null;
  int get _mySeat => widget.room?.mySeat ?? (_vsComputer ? 0 : _turn);

  /// Whether this device may take the current shot.
  bool get _myTurn =>
      _online ? _turn == _mySeat : (!_vsComputer || _turn == 0);

  /// Knocked out, but still watching the rest play it out.
  bool get _spectating {
    final me = _sim.seat(_mySeat);
    return (_online || _vsComputer) && me != null && !me.alive;
  }

  /// Aiming needs a live link and a present opponent — otherwise the shot
  /// would be lost, or fired into a match the peer is not watching.
  /// One meter per seat. Two sit side by side as the design shows; three or
  /// more wrap so five still fit on a phone without shrinking to nothing.
  Widget _meterBoard() {
    final pens = [..._sim.pens]..sort((a, b) => a.seat.compareTo(b.seat));

    if (pens.length <= 2) {
      return Row(
        children: [
          for (var i = 0; i < pens.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _meterCard(pens[i], compact: false)),
          ],
        ],
      );
    }

    return LayoutBuilder(builder: (context, c) {
      // Three across reads well at phone width; five becomes 3 + 2.
      const perRow = 3;
      const gap = 8.0;
      final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final p in pens)
            SizedBox(width: w, child: _meterCard(p, compact: true)),
        ],
      );
    });
  }

  Widget _meterCard(Pen pen, {required bool compact}) => _MeterCard(
        name: widget.nameFor(pen.seat),
        color: PF.inkFor(pen.seat),
        badge: PF.badgeFor(pen.seat),
        pen: pen,
        compact: compact,
        isTurn: pen.seat == _turn,
        isMe: (_online || _vsComputer) && pen.seat == _mySeat,
      );

  /// Give the charge pad a little more room on tall screens, without letting
  /// it crowd the table on short ones.
  double _padHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    // Two-stage controls need more room than the old single power bar.
    return (h * 0.15).clamp(118.0, 168.0);
  }

  /// A one-line explanation of why play is paused, or null when all is well.
  String? get _statusLine {
    if (_spectating) {
      return 'YOU ARE OUT · WATCHING ${_sim.living.length} PENS LEFT';
    }
    final r = widget.room;
    if (r == null) return null;
    if (r.peerMissingFor != null) {
      final secs = r.peerMissingFor!.inSeconds;
      return 'OPPONENT DISCONNECTED · ${secs}s';
    }
    return switch (r.link) {
      LinkState.connecting => 'CONNECTING…',
      LinkState.reconnecting => 'RECONNECTING…',
      LinkState.dropped => 'CONNECTION LOST',
      LinkState.live => r.peerPresent ? null : 'WAITING FOR OPPONENT',
    };
  }

  Widget _statusBanner(String text) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: PF.orange.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PF.orange, width: 2),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: PF.bold(11.5, w: 700, ls: 1.2, color: PF.black),
        ),
      );

  bool get _canAct {
    if (_botThinking || _awaitingHandover || _spectating) return false;
    final r = widget.room;
    if (r == null) return true;
    return r.link == LinkState.live && r.peerPresent;
  }

  @override
  void initState() {
    super.initState();
    _sim = Sim.table(
        width: kTableW, height: kTableH, players: widget.playerCount);
    // Room for the opening frame, every tick up to the hard stop, and the
    // authoritative snapshot an online peer may send.
    _replay = Float64List(
        (kMaxTicks + 2) * widget.playerCount * _kReplayStride);
    final ai = widget.ai;
    if (ai != null) _bot = PenAi(ai);
    _anim = AnimationController(vsync: this)
      ..addListener(_onFrame)
      ..addStatusListener(_onAnimStatus);

    Analytics.screen('battle');
    Analytics.matchStarted(_mode, players: widget.playerCount);

    final r = widget.room;
    if (r != null) {
      r.onPeerFlick = (seat, dir, power, grab, settled, nextTurn) {
        if (!mounted) return;
        _runFlick(seat, dir, power, grab,
            authoritative: settled, nextTurn: nextTurn);
      };
      r.onPeerRematch = () {
        if (mounted) _reset();
      };
      r.onPeerForfeit = () {
        if (!mounted) return;
        _showForfeit();
      };
      r.addListener(_onRoomChange);

      // Resume mid-match if we are reconnecting into a game in progress.
      if (r.lastSnapshot != null) {
        _sim.restore(r.lastSnapshot!);
        _turn = r.lastTurn;
      }
    }
  }

  void _onRoomChange() {
    if (mounted) setState(() {});
  }

  /// Confirm before abandoning a live match — leaving hands the other
  /// player the win, so it should never happen on a stray tap.
  Future<void> _confirmLeave() async {
    final leaving = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PF.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: PF.black, width: 2.5),
        ),
        title: Text('Leave the table?', style: PF.marker(24)),
        content: Text(
          _online
              ? 'Your opponent wins by forfeit. You can rejoin from the home '
                  'screen while the table is still live.'
              : 'The match will be lost.',
          style: PF.bold(13.5, w: 500, h: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('KEEP PLAYING',
                style: PF.bold(13, w: 700, color: PF.black)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('LEAVE', style: PF.bold(13, w: 700, color: PF.red)),
          ),
        ],
      ),
    );

    if (leaving != true || !mounted) return;
    await ActiveSession.clear();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// The opponent never came back — the match is over.
  void _showForfeit() {
    final r = widget.room;
    if (r == null) return;
    r.closeRoom();
    ActiveSession.clear();
    Analytics.matchEnded(_mode, outcome: 'forfeit', turns: _turnsPlayed);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => WinScreen(
        winnerName: widget.nameFor(r.mySeat),
        winnerColor: PF.inkFor(r.mySeat),
        youWon: true,
        subtitle: 'OPPONENT LEFT THE DESK',
        onRematch: () => Navigator.of(context).popUntil((x) => x.isFirst),
      ),
    ));
  }

  @override
  void dispose() {
    widget.room?.removeListener(_onRoomChange);
    _anim.dispose();
    _paint.dispose();
    super.dispose();
  }

  void _onFrame() {
    if (_replayFrames == 0) return;
    final i = (_anim.value * (_replayFrames - 1)).round();
    if (i < 0 || i >= _replayFrames) return;
    _applyFrame(i);

    // The pens repaint straight from the sim, so most frames need no rebuild
    // at all. Only when the meters, a knockout or the danger band actually
    // change is the rest of the screen worth touching — a handful of times
    // per flick instead of sixty times a second.
    _paint.value++;
    final board = _boardSignature();
    if (board != _boardSig) {
      _boardSig = board;
      setState(() {});
    }
  }

  /// Record the sim's current state into replay slot [frame].
  void _capture(Sim s, int frame) {
    final pens = s.pens;
    var o = frame * pens.length * _kReplayStride;
    for (var i = 0; i < pens.length; i++) {
      final p = pens[i];
      _replay[o++] = p.pos.x;
      _replay[o++] = p.pos.y;
      _replay[o++] = p.angle;
      _replay[o++] = p.ink;
      _replay[o++] = p.alive ? 1 : 0;
      _replay[o++] = p.vel.x;
      _replay[o++] = p.vel.y;
    }
  }

  /// Put the sim back into the state recorded at [frame].
  void _applyFrame(int frame) {
    final pens = _sim.pens;
    var o = frame * pens.length * _kReplayStride;
    for (var i = 0; i < pens.length; i++) {
      final p = pens[i];
      p.pos = Vec2(_replay[o], _replay[o + 1]);
      p.angle = _replay[o + 2];
      p.ink = _replay[o + 3];
      p.alive = _replay[o + 4] != 0;
      p.vel = Vec2(_replay[o + 5], _replay[o + 6]);
      p.spin = 0;
      o += _kReplayStride;
    }
  }

  /// Everything on screen that is not a pen, folded into one number: each
  /// meter's ink, who is out, and who is in the danger band. Comparing this
  /// is what tells playback whether a rebuild is actually needed.
  double _boardSignature() {
    var sig = 0.0;
    final pens = _sim.pens;
    for (var i = 0; i < pens.length; i++) {
      final p = pens[i];
      sig = sig * 512 +
          p.ink.round() * 4 +
          (p.alive ? 2 : 0) +
          (penInDanger(p) ? 1 : 0);
    }
    return sig;
  }

  void _onAnimStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    // Guard against completions that are not the end of a flick — without
    // this, a stray completion wipes the contact point the player just
    // locked in and silently sends them back to stage one.
    if (!_busy) return;
    setState(() {
      _busy = false;
      _splatAt = null;
      _clock = 8;
    });
    if (_sim.isOver) {
      final w = _sim.winnerSeat ?? 0;
      Analytics.matchEnded(
        _mode,
        outcome: (!_online && !_vsComputer)
            ? 'decided'
            : (w == _mySeat ? 'win' : 'loss'),
        turns: _turnsPlayed,
      );
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WinScreen(
            winnerName: widget.nameFor(w),
            winnerColor: PF.inkFor(w),
            youWon: !_online || w == _mySeat,
            onRematch: () {
              Navigator.of(context).pop();
              widget.room?.sendRematch();
              _reset();
            },
          ),
        ));
      });
    } else {
      // Apply the turn decided when the flick was issued. Never derive it
      // from local animation timing — the two clients finish at different
      // moments and would drift apart.
      final next = _pendingTurn ?? _sim.nextLivingSeat(_turn);
      setState(() {
        _turn = next;
        _contact = 0.5;
        _contactLocked = false;
        // More than two on one device means the handover needs a beat, or
        // the next player inherits a half-aimed shot.
        _awaitingHandover =
            widget.passAndPlay && widget.playerCount > 2 && !_sim.isOver;
      });
      _maybePlayBot();
    }
  }

  /// Hand play to the computer when it is its turn.
  void _maybePlayBot() {
    final bot = _bot;
    if (bot == null || _botThinking || _busy || _turn == 0) return;
    if (_sim.isOver) return;

    setState(() => _botThinking = true);
    // A beat of "thinking" so the shot does not fire the instant the pens
    // stop — it reads as an opponent taking aim.
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      final seat = _turn;
      final shot = bot.chooseShot(_sim, seat);
      setState(() => _botThinking = false);
      if (shot == null) return;
      _runFlick(seat, shot.direction, shot.power, shot.grab,
          nextTurn: _sim.nextLivingSeat(seat));
    });
  }

  void _reset() {
    setState(() {
      _sim = Sim.table(
          width: kTableW, height: kTableH, players: widget.playerCount);
      _turn = 0;
      _busy = false;
      _splatAt = null;
      _clock = 8;
      _dragStart = null;
      _dragNow = null;
      _grabOnPen = null;
      _pendingTurn = null;
      _botThinking = false;
      _contact = 0.5;
      _contactLocked = false;
      _replayFrames = 0;
      _boardSig = _boardSignature();
    });
  }

  /// Run a flick: simulate, capture every tick as a frame, then play it back.
  /// If [authoritative] is given (peer's own settled result) we snap to it at
  /// the end, which eliminates any float drift between the two clients.
  void _runFlick(int seat, Vec2 dir, double power, Vec2? grab,
      {List<dynamic>? authoritative, int? nextTurn}) {
    final sim = _sim.copy()..applyFlick(seat, dir, power, grab: grab);

    var frames = 0;
    _capture(sim, frames++);
    Vec2? impact;
    var ticks = 0;
    while (ticks < kMaxTicks) {
      sim.step(onImpact: (v) => impact ??= v);
      _capture(sim, frames++);
      ticks++;
      if (sim.allRested) break;
    }

    if (authoritative != null) {
      sim.restore(authoritative);
      _capture(sim, frames++);
    }
    _replayFrames = frames;

    setState(() {
      _busy = true;
      _splatAt = impact;
      _splatColor = PF.inkFor(seat);
      // Online, the flicker decides the next turn and ships it. Offline,
      // alternate locally. Either way it is decided here, not when the
      // animation happens to finish.
      _pendingTurn = nextTurn ?? (_online ? _turn : _sim.nextLivingSeat(seat));
      _boardSig = _boardSignature();
    });

    _turnsPlayed++;
    _anim
      ..duration = Duration(milliseconds: (frames * 1000 / 60).round())
      ..forward(from: 0);
  }

  /// How this match is being played, for analytics.
  String get _mode =>
      _online ? 'online' : (_vsComputer ? 'computer' : 'local');

  /// Shots taken this match, so we can see how long games actually run.
  int _turnsPlayed = 0;

  /// The seat this device is currently playing.
  int get _actingSeat => _online ? _mySeat : _turn;

  /// Exposed for tests: the pen the current player is about to flick.
  @visibleForTesting
  Pen? get debugActingPen => _sim.seat(_actingSeat);

  /// Exposed for tests: take the locked-in shot with the given pull vector
  /// (in table units), bypassing pointer hit-testing.
  @visibleForTesting
  void debugFireShot(Offset pull) {
    final at = _contactPoint;
    if (at == null) return;
    setState(() {
      _dragStart = Offset(at.x, at.y);
      _dragNow = Offset(at.x - pull.dx, at.y - pull.dy);
      _grabOnPen = at;
    });
    _release();
  }

  /// Exposed for tests: move the contact slider.
  @visibleForTesting
  void debugSetContact(double v) => setState(() => _contact = v);

  /// Exposed for tests: whether stage one has been completed.
  @visibleForTesting
  bool get debugContactLocked => _contactLocked;

  /// Exposed for tests: the strike point the shot will use.
  @visibleForTesting
  Vec2? get debugContactPoint => _contactPoint;

  /// The chosen strike point on the acting pen, in table coordinates.
  /// Derived from [_contact] so the slider and the physics can never
  /// disagree — there is one source of truth for where the pen is hit.
  Vec2? get _contactPoint {
    final me = _sim.seat(_actingSeat);
    if (me == null || !me.alive) return null;
    final (s1, s2) = me.segment;
    return Vec2(
      s1.x + (s2.x - s1.x) * _contact,
      s1.y + (s2.y - s1.y) * _contact,
    );
  }

  /// Stage two: aiming can begin anywhere on the table, because the contact
  /// point is already decided. This is what makes the drag forgiving —
  /// precision lives in the slider, not in where your thumb lands.
  void _beginAim(Vec2 local) {
    if (!_contactLocked) return;
    final me = _sim.seat(_actingSeat);
    if (me == null || !me.alive) return;

    setState(() {
      _dragStart = Offset(local.x, local.y);
      _dragNow = _dragStart;
      _grabOnPen = _contactPoint;
    });
  }

  /// Drop the current aim without taking the shot.
  void _abortDrag() {
    if (_dragStart == null) return;
    setState(() {
      _dragStart = null;
      _dragNow = null;
      _grabOnPen = null;
    });
  }

  void _release() {
    final start = _dragStart, now = _dragNow, grabbed = _grabOnPen;
    setState(() {
      _dragStart = null;
      _dragNow = null;
      _grabOnPen = null;
    });
    if (start == null || now == null) return;

    final pull = start - now; // slingshot: drag back, fly forward
    final power = (pull.distance / kPullRange).clamp(0.0, 1.0);
    if (power < 0.08) return; // a nudge is not a shot
    setState(() => _contactLocked = false); // back to stage one next turn

    final dir = Vec2(pull.dx, pull.dy);
    final seat = _online ? _mySeat : _turn;
    // Recompute rather than trusting the drag-start capture — the pen may
    // have settled since, and the strike must land where the ring is drawn.
    final grab = _contactPoint ?? grabbed ?? Vec2(start.dx, start.dy);

    // Simulate authoritatively on our side, then tell the peer.
    final next = _sim.nextLivingSeat(seat); // skips anyone knocked out
    if (_online) {
      final probe = _sim.copy()..applyFlick(seat, dir, power, grab: grab);
      probe.settle();
      widget.room!
          .sendFlick(seat, dir, power, grab, probe.snapshot(), next);
    }
    _runFlick(seat, dir, power, grab, nextTurn: next);
  }

  double get _power {
    final s = _dragStart, n = _dragNow;
    if (s == null || n == null) return 0;
    return ((s - n).distance / kPullRange).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final anyDanger = _sim.pens.any(penInDanger);

    return PopScope(
      // Android's back button and the browser back gesture both land here;
      // abandoning a live match should never be a single accidental tap.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      body: Stack(children: [
      PaperBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              // Beyond this the table stops growing and just centres — a
              // full-width table on a desktop monitor is unplayable.
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
            children: [
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _meterBoard(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _turnPill(),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _confirmLeave,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: PF.black, width: 2),
                      ),
                      child: Text('✕', style: PF.bold(15, w: 700)),
                    ),
                  ),
                ],
              ),
              if (_statusLine != null) ...[
                const SizedBox(height: 8),
                _statusBanner(_statusLine!),
              ],
              const SizedBox(height: 12),
              Expanded(child: _table(anyDanger)),
              const SizedBox(height: 12),
              _pad(),
              const SizedBox(height: 16),
            ],
              ),
            ),
          ),
        ),
      ),
      if (_awaitingHandover) _handover(),
      ]),
      ),
    );
  }

  /// "Pass the pen" — floods to the next player's ink so it reads across a
  /// desk, and hides the table until they confirm they have the device.
  Widget _handover() {
    final color = PF.inkFor(_turn);
    final prev = widget.nameFor(
        (_turn - 1 + widget.playerCount) % widget.playerCount);

    return Positioned.fill(
      child: Container(
        color: color,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('EYES OFF, $prev',
                      textAlign: TextAlign.center,
                      style: PF.code(13,
                          color: Colors.white.withValues(alpha: .75),
                          ls: 3)),
                  const SizedBox(height: 14),
                  Text('PASS\nTHE PEN',
                      textAlign: TextAlign.center,
                      style: PF.marker(52, color: Colors.white, h: .92)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text("${widget.nameFor(_turn)}'S TURN",
                        style: PF.bold(15,
                            color: Colors.white, w: 700, ls: .9)),
                  ),
                  const SizedBox(height: 26),
                  ChunkyButton(
                    onTap: () =>
                        setState(() => _awaitingHandover = false),
                    background: Colors.white,
                    shadow: Colors.black.withValues(alpha: .3),
                    minHeight: 56,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 34, vertical: 14),
                    child: Text("I'VE GOT IT",
                        style: PF.bold(18, w: 800, ls: .8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _turnPill() {
    final name = widget.nameFor(_turn);
    final label = _online
        ? (_myTurn ? 'YOUR TURN' : '$name IS AIMING')
        : _vsComputer
            ? (_botThinking
                ? '$name IS AIMING'
                : _turn == 0
                    ? 'YOUR TURN'
                    : '$name TO FLICK')
            : '$name TO FLICK';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
          color: PF.black, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: PF.bold(12, color: Colors.white, w: 700, ls: 1.2)),
          const SizedBox(width: 10),
          Text('0:0$_clock', style: PF.code(13, color: PF.orange)),
        ],
      ),
    );
  }

  Widget _table(bool danger) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(builder: (context, c) {
          final scale =
              math.min(c.maxWidth / kTableW, c.maxHeight / kTableH);
          final locked = _busy || !_myTurn || !_canAct;
          return Center(
            child: SizedBox(
              key: kTableKey,
              width: kTableW * scale,
              height: kTableH * scale,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: locked
                    ? null
                    : (e) => _beginAim(Vec2(e.localPosition.dx / scale,
                        e.localPosition.dy / scale)),
                onPointerMove: locked || _dragStart == null
                    ? null
                    : (e) {
                        // Aiming moves at pointer rate. The overlay and the
                        // power readout listen for this rather than the whole
                        // screen rebuilding on every move.
                        _dragNow = Offset(e.localPosition.dx / scale,
                            e.localPosition.dy / scale);
                        _paint.value++;
                      },
                onPointerUp: locked ? null : (_) => _release(),
                // A cancelled pointer is the system interrupting the gesture
                // (incoming call, scroll steal) — not the player letting go.
                // Firing the shot there would spend their turn on an input
                // they never made, so abort the drag instead.
                onPointerCancel: locked ? null : (_) => _abortDrag(),
                child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PF.black, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x2E14161A),
                        offset: Offset(0, 6),
                        blurRadius: 0)
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Stack(
                    children: [
                      // Grid and label never change, so they get their own
                      // layer and are rasterized once rather than re-recorded
                      // behind every frame of play.
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: const GridPaperPainter(),
                            isComplex: true,
                            willChange: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 0, 0),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text('TABLE EDGE',
                                    style: PF.code(10.5,
                                        color:
                                            PF.black.withValues(alpha: .45))),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Edge-danger inset: resolves the design's flag #1.
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: DashedRect(
                            radius: 14,
                            strokeWidth: 1.5,
                            color: danger
                                ? PF.red
                                : PF.black.withValues(alpha: .25),
                          ),
                        ),
                      ),
                      // Every pen on a single canvas, repainting straight off
                      // the sim. As a widget each, a flick meant rebuilding,
                      // laying out and re-layering five rotated glyphs sixty
                      // times a second.
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: kPensKey,
                            painter: _PensPainter(
                              sim: _sim,
                              scale: scale,
                              repaint: _paint,
                            ),
                          ),
                        ),
                      ),
                      if (_splatAt != null) _splat(scale),
                      // Stage one feedback: show where the shot will land on
                      // the pen, before any aiming happens.
                      if (!locked && _dragStart == null) _contactMarker(scale),
                      if (_dragStart != null && _myTurn) _aimLine(scale),
                    ],
                  ),
                ),
                ),
              ),
            ),
          );
        }),
      );

  Widget _aimLine(double scale) => ValueListenableBuilder<int>(
        valueListenable: _paint,
        builder: (_, _, _) => _aimOverlay(scale),
      );

  Widget _aimOverlay(double scale) {
    final seat = _online ? _mySeat : _turn;
    final me = _sim.seat(seat);
    if (me == null || !me.alive) return const SizedBox.shrink();
    final pull = _dragStart! - _dragNow!;
    final dir = Vec2(pull.dx, pull.dy).normalized;
    final len = 40 + _power * 110;

    // Derive the anchor live from the contact fraction rather than reusing
    // the value captured at drag start: the pen can still be settling, and a
    // cached point would drift off the pen it is supposed to be on.
    final anchor = _contactPoint ?? me.pos;

    // Preview where the pen will pivot: torque has the same sign the sim
    // computes, so the arc curls the way the pen will actually turn.
    final r = anchor - me.pos;
    final torque = r.x * dir.y - r.y * dir.x;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _AimPainter(
            from: Offset(anchor.x * scale, anchor.y * scale),
            to: Offset(
              (anchor.x + dir.x * len) * scale,
              (anchor.y + dir.y * len) * scale,
            ),
            // Where the finger has dragged to — the slingshot band.
            pullTo: Offset(_dragNow!.dx * scale, _dragNow!.dy * scale),
            pivot: Offset(me.pos.x * scale, me.pos.y * scale),
            torque: torque,
            power: _power,
          ),
        ),
      ),
    );
  }

  /// A ring on the acting pen at the chosen strike point.
  Widget _contactMarker(double scale) {
    final at = _contactPoint;
    if (at == null) return const SizedBox.shrink();
    final r = _contactLocked ? 13.0 : 11.0;

    return Positioned(
      left: at.x * scale - r,
      top: at.y * scale - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: _contactLocked ? .9 : .55),
            border: Border.all(
              color: _contactLocked ? PF.orange : PF.black.withValues(alpha: .5),
              width: _contactLocked ? 3 : 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _splat(double scale) {
    final at = _splatAt!;
    return Positioned(
      left: at.x * scale - 32,
      top: at.y * scale - 32,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey('${at.x}-${at.y}'),
          tween: Tween(begin: .4, end: 1.15),
          duration: const Duration(milliseconds: 300),
          builder: (_, v, _) => Opacity(
            opacity: (1 - (v - .4) / .75).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: v,
              child: SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(painter: _SplatPainter(_splatColor)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The shot is taken in two stages, because doing both at once meant
  /// every shot needed a pixel-accurate grab on a small pen:
  ///
  ///   1. Choose WHERE on your pen to strike, with a slider. Precision lives
  ///      here, where there is room for it.
  ///   2. Drag anywhere on the table to aim and set power. Forgiving, because
  ///      the contact point is already decided.
  Widget _pad() {
    final locked = _busy || !_myTurn || !_canAct;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Opacity(
        opacity: locked ? .5 : 1,
        child: Container(
          constraints: BoxConstraints(
            minHeight: _padHeight(context),
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(20),
          ),
          child: DashedRect(
            radius: 20,
            color: _contactLocked
                ? PF.orange
                : PF.black.withValues(alpha: .4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: locked
                  ? _padMessage()
                  : _contactLocked
                      ? _aimStage()
                      : _contactStage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _padMessage() => Center(
        child: Text(
          _busy
              ? 'PENS SETTLING…'
              : _spectating
                  ? 'YOU ARE OUT'
                  : _awaitingHandover
                      ? 'PASS THE DEVICE'
                      : 'WAIT YOUR TURN',
          style: PF.bold(13, w: 700, ls: 1.2),
        ),
      );

  /// Stage one: pick the strike point along the pen.
  Widget _contactStage() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('STEP 1 · WHERE TO HIT',
                    style: PF.bold(12, w: 700, ls: 1.2)),
              ),
              Text(_contactLabel, style: PF.code(12, color: PF.orange)),
            ],
          ),
          const SizedBox(height: 8),
          _ContactSlider(
            value: _contact,
            color: PF.inkFor(_actingSeat),
            onChanged: (v) => setState(() => _contact = v),
          ),
          const SizedBox(height: 8),
          ChunkyButton(
            onTap: () => setState(() => _contactLocked = true),
            background: PF.black,
            minHeight: 40,
            radius: 10,
            shadowOffset: 3,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('LOCK IT IN',
                style: PF.bold(13, color: Colors.white, w: 800, ls: .8)),
          ),
        ],
      );

  /// Stage two: aim and power.
  Widget _aimStage() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The percentage and the bar are the only things that move while
          // aiming, so they are the only things that rebuild.
          ValueListenableBuilder<int>(
            valueListenable: _paint,
            builder: (_, _, _) {
              final power = _power;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('STEP 2 · DRAG TO AIM',
                            style: PF.bold(12, w: 700, ls: 1.2)),
                      ),
                      Text('${(power * 100).round()}%',
                          style: PF.code(13, color: PF.red)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(
                      children: [
                        Container(height: 14, color: PF.meterTrack),
                        FractionallySizedBox(
                          widthFactor: power,
                          child: Container(
                            height: 14,
                            decoration: const BoxDecoration(
                              gradient:
                                  LinearGradient(colors: [PF.red, PF.orange]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Drag anywhere, pull back, release',
                    style: PF.code(11,
                        color: PF.black.withValues(alpha: .55))),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _contactLocked = false;
                  _dragStart = null;
                  _dragNow = null;
                  _grabOnPen = null;
                }),
                child: Text('CHANGE',
                    style: PF.bold(11.5, w: 700, ls: .6, color: PF.blue)),
              ),
            ],
          ),
        ],
      );

  String get _contactLabel {
    if (_contact < 0.22) return 'BACK END';
    if (_contact < 0.42) return 'BACK';
    if (_contact < 0.58) return 'CENTRE';
    if (_contact < 0.78) return 'FRONT';
    return 'NIB END';
  }

  /// A one-line explanation of why play is paused, or null when all is well.
}

/// Picks the strike point along the pen, drawn as the pen itself so the
/// control reads as what it does. Precision lives here rather than in a
/// pixel-accurate grab on the table.
class _ContactSlider extends StatelessWidget {
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _ContactSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          const inset = 14.0;
          final track = c.maxWidth - inset * 2;

          void update(double dx) =>
              onChanged(((dx - inset) / track).clamp(0.0, 1.0));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => update(e.localPosition.dx),
            onHorizontalDragStart: (e) => update(e.localPosition.dx),
            onHorizontalDragUpdate: (e) => update(e.localPosition.dx),
            child: SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The pen body, as the track.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: inset),
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                  // Nib end, so "which way round" is never ambiguous.
                  Positioned(
                    right: inset - 4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                          color: PF.black, shape: BoxShape.circle),
                    ),
                  ),
                  // The chosen strike point.
                  Positioned(
                    left: inset + track * value - 13,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: PF.orange, width: 3),
                        boxShadow: offsetShadow(2, const Color(0x3314161A)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _MeterCard extends StatelessWidget {
  final String name, badge;
  final Color color;
  final Pen pen;

  /// Tighter layout when three or more meters share the row.
  final bool compact;

  /// Whose shot it is, and which one is this device's own pen.
  final bool isTurn, isMe;

  const _MeterCard({
    required this.name,
    required this.color,
    required this.badge,
    required this.pen,
    this.compact = false,
    this.isTurn = false,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final out = !pen.alive;
    final chip = compact ? 20.0 : 24.0;

    return Opacity(
      opacity: out ? .45 : 1,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 11, vertical: compact ? 7 : 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          // The active player's meter is outlined in their own ink so the
          // turn is readable at a glance with five cards on screen.
          border: Border.all(
            color: isTurn ? color : PF.black,
            width: isTurn ? 3 : 2.5,
          ),
          boxShadow: offsetShadow(3, const Color(0x3314161A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: chip,
                  height: chip,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(compact ? 6 : 7)),
                  child: Text(badge,
                      style: PF.bold(compact ? 10 : 12,
                          color: Colors.white, w: 700)),
                ),
                SizedBox(width: compact ? 5 : 7),
                Expanded(
                  child: Text(
                    out ? 'OUT' : name,
                    overflow: TextOverflow.ellipsis,
                    style: PF.bold(compact ? 10.5 : 12, w: 700, ls: .5),
                  ),
                ),
                if (!compact || !out)
                  Text('${pen.ink.round()}',
                      style: PF.code(compact ? 11 : 14)),
              ],
            ),
            SizedBox(height: compact ? 5 : 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(height: compact ? 8 : 11, color: PF.meterTrack),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    widthFactor: (pen.ink / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: compact ? 8 : 11,
                      decoration: BoxDecoration(
                        color: color,
                        border: isMe
                            ? Border.all(
                                color: Colors.white.withValues(alpha: .55),
                                width: 1.5)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exposes where each pen is actually drawn, so tests can assert the painted
/// pen and the contact ring agree on the same point.
abstract class PenPlacement {
  /// Centre of [seat]'s drawn pen, in the pen layer's own coordinates.
  Offset? centreForSeat(int seat);
}

/// Draws every pen on the table onto one canvas.
///
/// Repaints are driven by [repaint] rather than by rebuilding widgets, so a
/// flick costs one canvas pass per frame instead of a rebuild, a re-layout
/// and a fresh transform and clip layer for each pen.
class _PensPainter extends CustomPainter implements PenPlacement {
  final Sim sim;
  final double scale;

  _PensPainter({
    required this.sim,
    required this.scale,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// Where each seat's pen was last actually drawn, recorded by [paint]. Held
  /// rather than recomputed so a test checks the placement the canvas used,
  /// not a second copy of the same arithmetic that could drift from it.
  final List<Offset?> _drawnAt = List<Offset?>.filled(kMaxPlayers, null);

  @override
  Offset? centreForSeat(int seat) =>
      seat >= 0 && seat < _drawnAt.length ? _drawnAt[seat] : null;

  @override
  void paint(Canvas canvas, Size size) {
    final length = kPenLength * scale;
    final thickness = kPenRadius * 2 * scale;

    _drawnAt.fillRange(0, _drawnAt.length, null);
    for (final p in sim.pens) {
      if (!p.alive) continue;
      final centre = Offset(p.pos.x * scale, p.pos.y * scale);
      if (p.seat < _drawnAt.length) _drawnAt[p.seat] = centre;
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(p.angle);
      paintPen(
        canvas,
        color: PF.inkFor(p.seat),
        length: length,
        thickness: thickness,
        danger: penInDanger(p),
      );
      canvas.restore();
    }
  }

  // Frame-to-frame repaints come through [repaint]; this only has to catch a
  // rebuild that swaps in a different table or a resized one.
  @override
  bool shouldRepaint(covariant _PensPainter o) {
    // A rebuild hands over a fresh painter. Carry the recorded placements
    // across, or one that needs no repaint would report nothing drawn.
    _drawnAt.setRange(0, _drawnAt.length, o._drawnAt);
    return !identical(o.sim, sim) || o.scale != scale;
  }
}

/// Exposes the aim overlay's anchor so tests can assert it tracks the grab
/// point rather than the pen's centre.
abstract class AimAnchor {
  Offset get fromPoint;
}

class _AimPainter extends CustomPainter implements AimAnchor {
  final Offset from, to, pullTo, pivot;

  @override
  Offset get fromPoint => from;

  final double power, torque;
  _AimPainter({
    required this.from,
    required this.to,
    required this.pullTo,
    required this.pivot,
    required this.torque,
    required this.power,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final colour = Color.lerp(PF.orange, PF.red, power)!;

    // The slingshot band: grab point back to the finger.
    canvas.drawLine(
      from,
      pullTo,
      Paint()
        ..color = colour.withValues(alpha: .35)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
        pullTo, 6, Paint()..color = colour.withValues(alpha: .45));

    // Ring on the shaft marking exactly where the pen was caught.
    canvas.drawCircle(
      from,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      from,
      8,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Spin preview: an arc around the pen's centre, curling the way the pen
    // will rotate. Only worth drawing when the pull is meaningfully off-centre.
    final lever = (from - pivot).distance;
    if (lever > 10 && power > 0.05) {
      final sweep = (torque.sign) * (0.5 + power * 0.9);
      final radius = (lever * 0.62).clamp(14.0, 46.0);
      canvas.drawArc(
        Rect.fromCircle(center: pivot, radius: radius),
        -1.2,
        sweep,
        false,
        Paint()
          ..color = colour.withValues(alpha: .7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Dashed launch guide, pointing where the pen will actually go.
    final paint = Paint()
      ..color = colour.withValues(alpha: .9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final d = to - from;
    final len = d.distance;
    if (len < 1) return;
    final step = d / len;
    for (double i = 0; i < len; i += 14) {
      canvas.drawLine(
          from + step * i, from + step * math.min(i + 8, len), paint);
    }
    canvas.drawCircle(to, 5 + power * 4, paint);
  }

  @override
  bool shouldRepaint(covariant _AimPainter o) =>
      o.to != to || o.pullTo != pullTo || o.from != from;
}

class _SplatPainter extends CustomPainter {
  final Color color;
  _SplatPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withValues(alpha: .85);
    canvas.drawCircle(const Offset(32, 32), 32, p);
    canvas.drawCircle(
        const Offset(58, 14), 13, Paint()..color = color.withValues(alpha: .7));
    canvas.drawCircle(
        const Offset(8, 52), 9, Paint()..color = color.withValues(alpha: .6));
    canvas.drawCircle(
        const Offset(60, 56), 6, Paint()..color = color.withValues(alpha: .55));
  }

  @override
  bool shouldRepaint(covariant _SplatPainter o) => o.color != color;
}
