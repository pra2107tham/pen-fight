import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/identity.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/paper.dart';
import 'battle.dart';
import 'lobby.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  bool _create = true;
  final _codeCtl = TextEditingController();

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  bool _busy = false;
  String? _joinError;
  int _capacity = 2;

  Future<void> _enter({required bool host}) async {
    final code = host ? Room.newCode() : _codeCtl.text.trim().toUpperCase();
    if (code.length != 4) return;

    setState(() {
      _busy = true;
      _joinError = null;
    });

    // Every device gets a stable id so a refresh rejoins the same seat
    // instead of being turned away as a third player.
    final id = await PlayerIdentity.mine();

    final JoinError? failure = host
        ? await Room.createRoom(code, id, capacity: _capacity)
        : await Room.validateRoom(code, id);

    if (!mounted) return;
    setState(() => _busy = false);

    if (failure != null) {
      setState(() => _joinError = failure.message);
      return;
    }

    // Remember it so a reload or a backgrounded app can offer to rejoin.
    await ActiveSession.save(code, isHost: host);

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WaitingRoom(
        code: code,
        isHost: host,
        playerId: id,
        capacity: host ? _capacity : null,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PaperBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                const SizedBox(height: 16),
                _tabs(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: _create ? _createBody() : _joinBody(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Row(
          children: [
            ChunkyButton(
              onTap: () => Navigator.of(context).pop(),
              minHeight: 44,
              radius: 12,
              borderWidth: 2,
              shadowOffset: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('‹', style: PF.bold(20, w: 700)),
            ),
            const SizedBox(width: 12),
            Text('Cloud desk', style: PF.marker(26)),
          ],
        ),
      );

  Widget _tabs() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: PF.black.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _tab('CREATE GAME', _create, () => setState(() => _create = true)),
            const SizedBox(width: 6),
            _tab('JOIN GAME', !_create, () => setState(() => _create = false)),
          ],
        ),
      );

  Widget _tab(String label, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label, style: PF.bold(13, w: 700, ls: .8)),
          ),
        ),
      );

  Widget _createBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: PF.black, width: 2.5),
              boxShadow: offsetShadow(4, const Color(0x3314161A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HOW IT WORKS',
                    style: PF.bold(11,
                        w: 700,
                        ls: 1.6,
                        color: PF.black.withValues(alpha: .55))),
                const SizedBox(height: 10),
                Text(
                  'Start a table and you get a four-letter code. Send it to '
                  'the other player — when they join, the fight begins.',
                  style: PF.bold(13, w: 500, h: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('HOW MANY PENS',
              style: PF.bold(11,
                  w: 700, ls: 1.6, color: PF.black.withValues(alpha: .55))),
          const SizedBox(height: 9),
          PlayerCountPicker(
            count: _capacity,
            enabled: !_busy,
            onChanged: (n) => setState(() => _capacity = n),
          ),
          const SizedBox(height: 18),
          ChunkyButton(
            onTap: kOnlineEnabled && !_busy ? () => _enter(host: true) : null,
            background: PF.green,
            minHeight: 60,
            child: Text(_busy ? 'STARTING…' : 'START A TABLE',
                style: PF.bold(19, color: Colors.white, w: 800, ls: .8)),
          ),
          if (_joinError != null) ...[
            const SizedBox(height: 12),
            _errorNotice(_joinError!),
          ],
          if (!kOnlineEnabled) ...[
            const SizedBox(height: 14),
            _keysNotice(),
          ],
        ],
      );

  Widget _joinBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Got a code?', style: PF.marker(30, h: 1.05)),
          const SizedBox(height: 8),
          Text('Type the four letters your friend sent you.',
              style: PF.bold(12.5,
                  w: 500, h: 1.4, color: PF.black.withValues(alpha: .6))),
          const SizedBox(height: 22),
          _CodeField(controller: _codeCtl, onChanged: () => setState(() {})),
          const SizedBox(height: 18),
          ChunkyButton(
            onTap: kOnlineEnabled && !_busy && _codeCtl.text.trim().length == 4
                ? () => _enter(host: false)
                : null,
            background: PF.black,
            minHeight: 58,
            child: Text(_busy ? 'CHECKING…' : 'JOIN TABLE',
                style: PF.bold(18, color: Colors.white, w: 800, ls: .8)),
          ),
          if (_joinError != null) ...[
            const SizedBox(height: 12),
            _errorNotice(_joinError!),
          ],
          if (!kOnlineEnabled) ...[
            const SizedBox(height: 14),
            _keysNotice(),
          ],
        ],
      );

  Widget _errorNotice(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PF.red.withValues(alpha: .1),
          border: const Border(left: BorderSide(color: PF.red, width: 4)),
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(12)),
        ),
        child: Text(text,
            style: PF.bold(13, w: 600, h: 1.4, color: PF.black)),
      );

  Widget _keysNotice() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PF.blue.withValues(alpha: .08),
          border: const Border(left: BorderSide(color: PF.blue, width: 4)),
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(12)),
        ),
        child: Text(
          'Online is switched off until Supabase keys are supplied via '
          '--dart-define=SUPABASE_URL=… and SUPABASE_ANON_KEY=…',
          style: PF.bold(12,
              w: 500, h: 1.5, color: PF.black.withValues(alpha: .7)),
        ),
      );
}

/// Four boxed cells, per the design's join screen.
class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _CodeField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = controller.text.toUpperCase();
    return Stack(
      children: [
        Row(
          children: List.generate(4, (i) {
            final filled = i < text.length;
            final active = i == text.length;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 3 ? 0 : 10),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active
                            ? PF.blue
                            : filled
                                ? PF.black
                                : PF.black.withValues(alpha: .35),
                        width: filled || active ? 2.5 : 2,
                      ),
                    ),
                    child: Text(filled ? text[i] : '',
                        style: PF.code(30)),
                  ),
                ),
              ),
            );
          }),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                UpperCaseFormatter(),
                FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
              ],
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue old, TextEditingValue now) =>
      now.copyWith(text: now.text.toUpperCase());
}

/// Live waiting room driven by Supabase presence.
class WaitingRoom extends StatefulWidget {
  final String code;
  final bool isHost;
  final String? playerId;

  /// Table size, known up front by the host; guests learn it on join.
  final int? capacity;

  const WaitingRoom({
    super.key,
    required this.code,
    required this.isHost,
    this.playerId,
    this.capacity,
  });

  @override
  State<WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<WaitingRoom> {
  late final Room _room;
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    _room = Room(
      code: widget.code,
      isHost: widget.isHost,
      id: widget.playerId,
      capacity: widget.capacity ?? 2,
      seat: widget.isHost ? 0 : Room.lastAssignedSeat,
    )..addListener(_onChange);
    _room.onStart = _launch;
    // If a match is already in progress under this code, pick it up rather
    // than dealing a fresh table.
    _room.loadState();
    _room.connect(name: widget.isHost ? 'HOST' : 'GUEST');
  }

  void _onChange() => setState(() {});

  void _launch() {
    if (_launched || !mounted) return;
    _launched = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => BattleScreen(
        room: _room,
        names: _room.playerNames,
      ),
    ));
  }

  @override
  void dispose() {
    _room.removeListener(_onChange);
    if (!_launched) _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = _room.isFull;
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChunkyButton(
                      onTap: () => Navigator.of(context).pop(),
                      minHeight: 44,
                      radius: 12,
                      borderWidth: 2,
                      shadowOffset: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('‹', style: PF.bold(20, w: 700)),
                    ),
                    const SizedBox(width: 12),
                    Text('Waiting room', style: PF.marker(26)),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: PF.black, width: 2.5),
                    boxShadow: offsetShadow(4, const Color(0x3314161A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR TABLE CODE',
                          style: PF.bold(11,
                              w: 700,
                              ls: 1.6,
                              color: PF.black.withValues(alpha: .55))),
                      const SizedBox(height: 10),
                      Text(widget.code, style: PF.code(40, ls: 2.4)),
                      const SizedBox(height: 14),
                      ChunkyButton(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: widget.code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Code ${widget.code} copied'),
                                duration: const Duration(seconds: 2)),
                          );
                        },
                        background: PF.blue,
                        minHeight: 48,
                        radius: 12,
                        shadowOffset: 3,
                        child: Text('COPY CODE',
                            style: PF.bold(13,
                                color: Colors.white, w: 700, ls: .8)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text('SEATS · ${_room.seats.length} / ${_room.capacity}',
                    style: PF.bold(11,
                        w: 700,
                        ls: 1.6,
                        color: PF.black.withValues(alpha: .55))),
                const SizedBox(height: 9),
                for (var i = 0; i < _room.capacity; i++) ...[
                  _seatRow(i),
                  const SizedBox(height: 8),
                ],
                if (_room.error != null) ...[
                  const SizedBox(height: 14),
                  Text(_room.error!,
                      style: PF.code(11.5, color: PF.red)),
                ],
                const Spacer(),
                if (widget.isHost)
                  ChunkyButton(
                    onTap: _room.seats.length >= 2
                        ? () {
                            _room.sendStart();
                            _launch();
                          }
                        : null,
                    background:
                        _room.seats.length >= 2 ? PF.green : PF.black,
                    minHeight: 60,
                    child: Text(
                      _room.seats.length >= 2
                          ? (full
                              ? 'START THE FIGHT'
                              : 'START WITH ${_room.seats.length}')
                          : 'WAITING FOR A CHALLENGER…',
                      style: PF.bold(_room.seats.length >= 2 ? 19 : 15,
                          color: Colors.white, w: 800, ls: .8),
                    ),
                  )
                else
                  Container(
                    height: 60,
                    alignment: Alignment.center,
                    child: Text(
                      full
                          ? 'Seated. Waiting for the host to start…'
                          : 'Connecting to the table…',
                      style: PF.bold(14,
                          w: 500, color: PF.black.withValues(alpha: .65)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seatRow(int index) {
    final taken = _room.seats.any((s) => s.index == index);
    final color = PF.inkFor(index);
    final isMe = index == _room.mySeat;
    final label = index == 0 ? 'HOST' : 'PLAYER ${index + 1}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: taken ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: taken
              ? PF.black.withValues(alpha: .55)
              : PF.black.withValues(alpha: .3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: taken ? color : PF.black.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(PF.badgeFor(index),
                style: PF.bold(14, color: Colors.white, w: 700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              taken ? (isMe ? '$label · YOU' : label) : 'empty seat',
              style: PF.bold(13, w: 700),
            ),
          ),
          Text(
            taken ? 'READY' : '—',
            style: PF.code(10.5,
                color: taken ? PF.green : PF.black.withValues(alpha: .4)),
          ),
        ],
      ),
    );
  }

}
