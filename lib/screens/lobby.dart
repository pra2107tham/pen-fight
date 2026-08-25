import 'package:flutter/material.dart';

import '../analytics.dart';
import '../game/sim.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/paper.dart';
import 'battle.dart';

/// Local pass-and-play setup: choose 2–5 pens, then fight on one device.
/// Mirrors the design's "Who's playing?" board.
class LocalLobbyScreen extends StatefulWidget {
  const LocalLobbyScreen({super.key});

  @override
  State<LocalLobbyScreen> createState() => _LocalLobbyScreenState();
}

class _LocalLobbyScreenState extends State<LocalLobbyScreen> {
  int _count = 2;

  @override
  void initState() {
    super.initState();
    Analytics.screen('local_lobby');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PaperBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Row(
                        children: [
                          ChunkyButton(
                            onTap: () => Navigator.of(context).pop(),
                            minHeight: 44,
                            radius: 12,
                            borderWidth: 2,
                            shadowOffset: 0,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            child: Text('‹', style: PF.bold(20, w: 700)),
                          ),
                          const SizedBox(width: 12),
                          Text("Who's playing?", style: PF.marker(26)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        children: [
                          Text('PENS ON THE DESK',
                              style: PF.bold(11,
                                  w: 700,
                                  ls: 1.6,
                                  color: PF.black.withValues(alpha: .55))),
                          const SizedBox(height: 9),
                          PlayerCountPicker(
                            count: _count,
                            onChanged: (n) => setState(() => _count = n),
                          ),
                          const SizedBox(height: 18),
                          for (var i = 0; i < _count; i++) ...[
                            _RosterRow(seat: i),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'TURN ORDER · clockwise from the blue pen',
                            style: PF.code(11.5,
                                color: PF.black.withValues(alpha: .5)),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: ChunkyButton(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BattleScreen(
                              names: [
                                for (var i = 0; i < _count; i++)
                                  PF.seatNames[i],
                              ],
                              passAndPlay: true,
                            ),
                          ),
                        ),
                        background: PF.black,
                        shadow: PF.red,
                        minHeight: 60,
                        child: Text('START THE FIGHT',
                            style: PF.bold(19,
                                color: Colors.white, w: 800, ls: .8)),
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

/// The 2/3/4/5 pill row, shared by the local and online lobbies.
class PlayerCountPicker extends StatelessWidget {
  final int count;
  final ValueChanged<int> onChanged;
  final bool enabled;

  const PlayerCountPicker({
    super.key,
    required this.count,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var n = 2; n <= kMaxPlayers; n++) ...[
            if (n > 2) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: enabled ? () => onChanged(n) : null,
                child: Opacity(
                  opacity: enabled ? 1 : .45,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: n == count ? PF.black : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PF.black, width: 2),
                    ),
                    child: Text('$n',
                        style: PF.bold(18,
                            w: 800,
                            color: n == count ? Colors.white : PF.black)),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}

class _RosterRow extends StatelessWidget {
  final int seat;
  const _RosterRow({required this.seat});

  @override
  Widget build(BuildContext context) {
    final color = PF.inkFor(seat);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PF.black.withValues(alpha: .6), width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(11)),
            child: Text(PF.badgeFor(seat),
                style: PF.bold(15, color: Colors.white, w: 700)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(PF.seatNames[seat],
                    style: PF.bold(14, w: 700, ls: .3)),
                const SizedBox(height: 5),
                Text(_penFor(seat),
                    style: PF.code(11.5,
                        color: PF.black.withValues(alpha: .55))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _penFor(int seat) => const [
        'Classic Blue ballpoint',
        'Red marker',
        'Black gel',
        'Green ballpoint',
        'Glitter gel',
      ][seat % 5];
}
