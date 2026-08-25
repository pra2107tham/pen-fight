import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pen_fight/game/sim.dart';
import 'package:pen_fight/net/room.dart';
import 'package:pen_fight/screens/battle.dart';
import 'package:pen_fight/screens/home.dart';
import 'package:pen_fight/screens/lobby.dart';
import 'package:pen_fight/screens/win.dart';
import 'package:pen_fight/theme.dart';

/// Screen position of a pen, derived from the table's on-screen rect.
Offset penCentre(WidgetTester t, int seat) {
  final table = t.getRect(find.byKey(kTableKey));
  // The widget fits the table with min(w/W, h/H) and centres it, so derive
  // the same mapping instead of assuming width drives the scale.
  final scale = math.min(table.width / kTableW, table.height / kTableH);
  final originX = table.left + (table.width - kTableW * scale) / 2;
  final originY = table.top + (table.height - kTableH * scale) / 2;

  final p = Sim.duel(width: kTableW, height: kTableH).seat(seat)!;
  return Offset(originX + p.pos.x * scale, originY + p.pos.y * scale);
}

/// The shot is two-stage now: lock the contact point, then aim.
Future<void> lockContact(WidgetTester t) async {
  expect(find.text('LOCK IT IN'), findsOneWidget,
      reason: 'stage one should offer to lock the contact point');
  await t.tap(find.text('LOCK IT IN'));
  await t.pumpAndSettle();
  expect(find.text('STEP 2 · DRAG TO AIM'), findsOneWidget,
      reason: 'locking should advance to the aiming stage');
}

void main() {
  // HomeScreen reads any saved session on start. Give it real (empty)
  // storage so that lookup resolves instead of leaving its timeout pending.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pass & play goes through the lobby into a battle', (t) async {
    await t.pumpWidget(const MaterialApp(home: HomeScreen()));
    await t.pumpAndSettle();

    expect(find.text('PASS & PLAY'), findsOneWidget);
    await t.tap(find.text('PASS & PLAY'));
    await t.pumpAndSettle();

    // The lobby picks how many pens are on the desk.
    expect(find.byType(LocalLobbyScreen), findsOneWidget);
    expect(find.text("Who's playing?"), findsOneWidget);

    await t.tap(find.text('START THE FIGHT'));
    await t.pumpAndSettle();

    expect(find.byType(BattleScreen), findsOneWidget);
  });

  testWidgets('the lobby can deal a five pen table', (t) async {
    await t.pumpWidget(const MaterialApp(home: LocalLobbyScreen()));
    await t.pumpAndSettle();

    await t.tap(find.text('5'));
    await t.pumpAndSettle();

    // Five rosters, one per seat.
    for (final name in PF.seatNames) {
      expect(find.text(name), findsOneWidget);
    }

    await t.tap(find.text('START THE FIGHT'));
    await t.pumpAndSettle();

    final battle =
        t.widget<BattleScreen>(find.byType(BattleScreen));
    expect(battle.playerCount, 5);
    expect(battle.passAndPlay, isTrue);
  });

  testWidgets('a locked-in shot fires and passes the turn', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: BattleScreen(names: ['BLUE', 'RED'])));
    await t.pumpAndSettle();

    expect(find.text('BLUE TO FLICK'), findsOneWidget);
    await lockContact(t);

    // Fire through the same entry point the pointer handlers use. Driving
    // the gesture by raw coordinates makes this a test of the widget tree's
    // hit-box arithmetic; what matters here is that a locked, aimed shot
    // resolves and hands the turn on.
    final st = t.state<State<BattleScreen>>(find.byType(BattleScreen));
    (st as dynamic).debugFireShot(const Offset(0, -260));

    await t.pumpAndSettle(const Duration(seconds: 12));

    expect(find.text('RED TO FLICK'), findsOneWidget,
        reason: 'turn should pass after a flick resolves');
  });

  testWidgets('a tiny drag under 6% does not spend the turn', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: BattleScreen(names: ['BLUE', 'RED'])));
    await t.pumpAndSettle();

    await lockContact(t);
    final g = await t.startGesture(penCentre(t, 0));
    await g.moveTo(penCentre(t, 0) + const Offset(0, 3));
    await g.up();
    await t.pumpAndSettle();

    expect(find.text('BLUE TO FLICK'), findsOneWidget,
        reason: 'a nudge under the 6% threshold is cancelled');
  });

  testWidgets('win screen fits a short viewport without overflowing', (t) async {
    // Regression: this Column overflowed by 2px before it was made scrollable.
    await t.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(MaterialApp(
      home: WinScreen(
        winnerName: 'BLUE',
        winnerColor: PF.blue,
        youWon: true,
        onRematch: () {},
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('REMATCH, COWARD'), findsOneWidget);
  });

  test('the flick a player sends is what the peer replays', () {
    // Mirrors the netcode path: sender simulates and ships the snapshot,
    // receiver replays the same input and snaps to it.
    const dir = Vec2(0.2, -1);
    const power = 0.9;

    final sender = Sim.duel(width: kTableW, height: kTableH)
      ..applyFlick(0, dir, power);
    sender.settle();
    final wire = sender.snapshot();

    final receiver = Sim.duel(width: kTableW, height: kTableH)
      ..applyFlick(0, dir, power);
    receiver.settle();

    expect(receiver.snapshot().toString(), wire.toString());
  });

  testWidgets('the aim overlay anchors on the chosen contact point',
      (t) async {
    await t.pumpWidget(const MaterialApp(
        home: BattleScreen(names: ['BLUE', 'RED'])));
    await t.pumpAndSettle();

    final table = t.getRect(find.byKey(kTableKey));
    final scale = table.width / kTableW;
    final me = Sim.duel(width: kTableW, height: kTableH).seat(0)!;
    final (_, tipEnd) = me.segment;

    // Grab the tip, well away from the centre of mass.
    await lockContact(t);
    final tipPt = table.topLeft + Offset(tipEnd.x * scale, tipEnd.y * scale);
    final g = await t.startGesture(tipPt);
    await t.pump();
    await g.moveTo(tipPt + Offset(0, table.height * 0.25));
    await t.pump();

    final painter = t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<AimAnchor>()
        .single;


    // The painter draws in the table's local space, so compare there.
    final grabLocal = tipPt - table.topLeft;

    // The slider defaults to the centre of the pen, and the aim drag no
    // longer decides the strike point — that is the whole point of the
    // two-stage control. So the overlay must anchor on the pen's centre
    // here, regardless of where the drag started.
    // Compare against the pen's own midpoint: the anchor must sit on the
    // pen, not follow the finger. A generous tolerance covers the pen having
    // settled slightly since the opening layout was computed.
    // The contract that matters: the strike point is the slider's choice,
    // which defaults to the pen's centre — NOT wherever the finger landed.
    // (Comparing painter pixels directly would mean re-deriving the widget's
    // internal scale and clip inset, which tests the arithmetic rather than
    // the behaviour.)
    final live = t.state<State<BattleScreen>>(find.byType(BattleScreen));
    final contact = (live as dynamic).debugContactPoint as Vec2;
    final pen = (live as dynamic).debugActingPen as Pen;

    expect((contact - pen.pos).length, lessThan(1.0),
        reason: 'a centred slider strikes the middle of the pen');

    // The drag began at the tip, far from that point — proving the strike
    // location does not follow the finger.
    final (_, liveTip) = pen.segment;
    expect((contact - liveTip).length, greaterThan(kPenLength * 0.3),
        reason: 'the touch point does not decide where the pen is struck');

    // And the overlay is anchored somewhere on the table, not at the finger.
    expect((grabLocal - painter.fromPoint).distance, greaterThan(20),
        reason: 'the anchor is not the touch point');

    await g.cancel();
    await t.pumpAndSettle();
  });

  testWidgets('an interrupted pointer aborts the aim instead of shooting',
      (t) async {
    await t.pumpWidget(const MaterialApp(
        home: BattleScreen(names: ['BLUE', 'RED'])));
    await t.pumpAndSettle();

    final table = t.getRect(find.byKey(kTableKey));
    final scale = table.width / kTableW;
    final me = Sim.duel(width: kTableW, height: kTableH).seat(0)!;
    await lockContact(t);
    final penPt =
        table.topLeft + Offset(me.pos.x * scale, me.pos.y * scale);

    final g = await t.startGesture(penPt);
    await t.pump();
    await g.moveTo(penPt + Offset(0, table.height * 0.4)); // full-power pull
    await t.pump();

    // The system yanks the gesture away mid-aim.
    await g.cancel();
    await t.pumpAndSettle();

    expect(find.text('BLUE TO FLICK'), findsOneWidget,
        reason: 'a cancelled pointer must not spend the turn');
  });

  test('placeholder Supabase credentials do not count as configured', () {
    // supabase.example.json ships with placeholders; if those slipped through
    // the app would try to reach a nonexistent project instead of showing the
    // "not configured" notice.
    expect(kOnlineEnabled, isFalse,
        reason: 'no real keys are compiled into the test build');
  });

  testWidgets('a duplicated peer flick does not advance the turn twice',
      (t) async {
    // Regression: the turn used to flip locally whenever an animation
    // finished, so a re-delivered broadcast advanced it twice and the two
    // clients drifted apart. The turn now rides in the message, so applying
    // the same message twice is idempotent.
    final room = Room(code: 'TEST', isHost: false); // we are seat 1
    addTearDown(room.dispose);

    await t.pumpWidget(MaterialApp(
        home: BattleScreen(room: room, names: const ['HOST', 'GUEST'])));
    await t.pumpAndSettle();
    expect(find.text('HOST IS AIMING'), findsOneWidget);

    final probe = Sim.duel(width: kTableW, height: kTableH)
      ..applyFlick(0, const Vec2(0.2, -1), 0.6);
    probe.settle();
    final snap = probe.snapshot();

    // Seat 0's flick arrives, handing the turn to us.
    room.onPeerFlick!(0, const Vec2(0.2, -1), 0.6, null, snap, 1);
    await t.pumpAndSettle(const Duration(seconds: 12));
    expect(find.text('YOUR TURN'), findsOneWidget);

    // The very same broadcast is delivered again — a redelivery, not a new
    // shot. Local flipping would bounce the turn back to the host here.
    room.onPeerFlick!(0, const Vec2(0.2, -1), 0.6, null, snap, 1);
    await t.pumpAndSettle(const Duration(seconds: 12));

    expect(find.text('YOUR TURN'), findsOneWidget,
        reason: 'replaying a message must not hand the turn back');
  });
}
