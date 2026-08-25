import 'package:flutter/material.dart';

import '../analytics.dart';
import '../net/identity.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/paper.dart';
import 'difficulty.dart';
import 'lobby.dart';
import 'online.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ActiveSession? _resumable;

  @override
  void initState() {
    super.initState();
    _checkForSession();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Analytics.screen('home');
  }

  Future<void> _checkForSession() async {
    final s = await ActiveSession.load();
    if (mounted) setState(() => _resumable = s);
  }

  Future<void> _rejoin(ActiveSession s) async {
    final id = await PlayerIdentity.mine();
    // Re-validate: the table may have expired or been closed while away.
    final failure = s.isHost ? null : await Room.validateRoom(s.code, id);

    if (!mounted) return;
    if (failure != null) {
      await ActiveSession.clear();
      if (!mounted) return;
      setState(() => _resumable = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${failure.message} — it may have expired')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => WaitingRoom(
            code: s.code,
            isHost: s.isHost,
            playerId: id,
          ),
        ))
        .then((_) => _checkForSession());
  }

  Future<void> _dismissSession() async {
    await ActiveSession.clear();
    if (mounted) setState(() => _resumable = null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PaperBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(56, 8, 22, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DESK RULES · NO CAPS OFF',
                        style: PF.code(12, color: PF.red, ls: 2.6)),
                    const SizedBox(height: 12),
                    Text('PEN\nFIGHT', style: PF.marker(62, h: .86)),
                    const SizedBox(height: 10),
                    Transform.rotate(
                      angle: -0.021,
                      child: Container(
                        width: 172,
                        height: 9,
                        decoration: BoxDecoration(
                            color: PF.blue,
                            borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const _CrossedPens(),
                    const SizedBox(height: 8),
                    if (_resumable != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 36),
                        child: _RejoinCard(
                          session: _resumable!,
                          onRejoin: () => _rejoin(_resumable!),
                          onDismiss: _dismissSession,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(right: 36),
                      child: Column(
                        children: [
                          _MenuCard(
                            title: 'PLAY ONLINE',
                            sub: 'Send a code. Find fresh victims.',
                            color: PF.green,
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (_) => const OnlineScreen()))
                                .then((_) => _checkForSession()),
                          ),
                          const SizedBox(height: 12),
                          _MenuCard(
                            title: 'PASS & PLAY',
                            sub: '2–5 pens. One desk. No mercy.',
                            color: PF.red,
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const LocalLobbyScreen())),
                          ),
                          const SizedBox(height: 12),
                          _MenuCard(
                            title: 'VS COMPUTER',
                            sub: 'It never blinks. Or flinches.',
                            color: PF.blue,
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const DifficultyScreen())),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!kOnlineEnabled)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(right: 36),
                        decoration: BoxDecoration(
                          color: PF.orange.withValues(alpha: .1),
                          border: const Border(
                              left: BorderSide(color: PF.orange, width: 4)),
                          borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(12)),
                        ),
                        child: Text(
                          'Online play needs Supabase keys — pass them with '
                          '--dart-define. Pass & Play works right now.',
                          style: PF.bold(12,
                              w: 500,
                              h: 1.45,
                              color: PF.black.withValues(alpha: .7)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Offers to put the player back into the match they left.
class _RejoinCard extends StatelessWidget {
  final ActiveSession session;
  final VoidCallback onRejoin, onDismiss;

  const _RejoinCard({
    required this.session,
    required this.onRejoin,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final mins = DateTime.now().difference(session.joinedAt).inMinutes;
    final ago = mins < 1 ? 'just now' : '${mins}m ago';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PF.orange, width: 2.5),
        boxShadow: offsetShadow(4, PF.orange.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('MATCH IN PROGRESS',
                    style: PF.bold(11, w: 700, ls: 1.6, color: PF.orange)),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('✕',
                      style: PF.bold(14,
                          w: 700, color: PF.black.withValues(alpha: .45))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(session.code, style: PF.code(28, ls: 2)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${session.isHost ? "you host" : "you joined"} · $ago',
                  style: PF.code(11,
                      color: PF.black.withValues(alpha: .55)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            onTap: onRejoin,
            background: PF.orange,
            minHeight: 48,
            radius: 12,
            shadowOffset: 3,
            child: Text('REJOIN TABLE',
                style: PF.bold(15, color: Colors.white, w: 800, ls: .8)),
          ),
        ],
      ),
    );
  }
}

class _CrossedPens extends StatelessWidget {
  const _CrossedPens();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 132,
        child: Stack(
          children: [
            Positioned(
                left: 94,
                top: 44,
                child: PenGlyph(
                    color: PF.blue, length: 190, angle: -0.279)),
            Positioned(
                left: 0,
                top: 66,
                child: PenGlyph(color: PF.red, length: 190, angle: 0.244)),
            Positioned(
              left: 120,
              top: 38,
              child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: PF.orange)),
            ),
            Positioned(
              left: 148,
              top: 22,
              child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PF.orange.withValues(alpha: .8))),
            ),
          ],
        ),
      );
}

class _MenuCard extends StatelessWidget {
  final String title, sub;
  final Color color;
  final VoidCallback? onTap;

  const _MenuCard({
    required this.title,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ChunkyButton(
        onTap: onTap,
        background: color,
        minHeight: 76,
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: PF.bold(22, color: Colors.white, w: 800)),
                  const SizedBox(height: 4),
                  Text(sub,
                      style: PF.bold(12.5,
                          w: 500,
                          h: 1.3,
                          color: Colors.white.withValues(alpha: .82))),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .18)),
              child: Text('›',
                  style: PF.bold(20, color: Colors.white, w: 700)),
            ),
          ],
        ),
      );
}
