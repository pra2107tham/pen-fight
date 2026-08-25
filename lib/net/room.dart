import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../game/sim.dart';
import '../theme.dart';

/// Supabase config, injected at build time:
///   flutter run --dart-define-from-file=supabase.json
const kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// True only for real credentials. The example file ships with placeholders,
/// so treat those as "not configured" rather than letting the app try to
/// connect to a nonexistent project and fail with a confusing network error.
bool get kOnlineEnabled =>
    kSupabaseUrl.startsWith('https://') &&
    !kSupabaseUrl.contains('YOURPROJECT') &&
    kSupabaseAnonKey.length > 40 &&
    !kSupabaseAnonKey.contains('paste-your-anon-key');

/// How long a vanished opponent has to come back before they forfeit.
const kPeerGrace = Duration(seconds: 30);

/// How long a room code stays joinable.
const kRoomTtl = Duration(hours: 2);

/// What went wrong when joining, in terms a player can act on.
enum JoinError { noSuchRoom, roomFull, expired, offline, unknown }

/// Last raw backend error, kept for diagnostics when a join fails.
String? lastFailure;

extension JoinErrorMessage on JoinError {
  String get message => switch (this) {
        JoinError.noSuchRoom => 'No table with that code',
        JoinError.roomFull => 'That table already has two players',
        JoinError.expired => 'That table has expired',
        JoinError.offline => 'Cannot reach the server',
        JoinError.unknown => 'Could not join that table',
      };
}

/// Live connection state, so the UI can tell the player what is happening
/// instead of silently freezing.
enum LinkState { connecting, live, reconnecting, dropped }

class Seat {
  final String id;
  final int index; // 0 = host, 1 = guest
  final String name;
  const Seat(this.id, this.index, this.name);
}

/// One networked table.
///
/// Turn-based, so no rollback or lockstep is needed: the player whose turn it
/// is simulates, animates, and broadcasts the input, its settled result, and
/// whose turn comes next. The peer replays the input for identical animation
/// then snaps to the authoritative snapshot.
class Room extends ChangeNotifier {
  final String code;
  final bool isHost;
  final String myId;

  /// How many seats this table was opened with (2–5).
  int capacity;

  /// Which seat this device holds. The host is always 0; guests are assigned
  /// the next free seat when they join.
  int seatIndex;

  RealtimeChannel? _channel;
  List<Seat> seats = [];
  LinkState link = LinkState.connecting;
  String? error;

  /// Counts down while the opponent is missing; null when they are present.
  Duration? peerMissingFor;
  Timer? _graceTimer;
  bool _peerEverSeen = false;

  /// Set when the opponent's grace period runs out.
  bool peerForfeited = false;

  void Function(int seat, Vec2 dir, double power, Vec2? grab,
      List<dynamic> settled, int nextTurn)? onPeerFlick;
  void Function()? onPeerRematch;
  void Function()? onStart;

  /// Fired when the opponent fails to return within [kPeerGrace].
  void Function()? onPeerForfeit;

  /// Latest state the peer sent, kept so a reconnecting client can resume
  /// mid-match rather than restarting from the opening layout.
  List<dynamic>? lastSnapshot;
  int lastTurn = 0;

  Room({
    required this.code,
    required this.isHost,
    String? id,
    this.capacity = 2,
    int? seat,
  })  : myId = id ?? const Uuid().v4(),
        seatIndex = seat ?? (isHost ? 0 : 1);

  int get mySeat => seatIndex;
  bool get isFull => seats.length >= capacity;

  /// Names for every seat at this table, for the battle screen.
  List<String> get playerNames => [
        for (var i = 0; i < capacity; i++)
          seats.firstWhere((s) => s.index == i,
              orElse: () => Seat('', i, PF.seatNames[i % 5])).name,
      ];

  /// With more than two players, "the peer" is everyone else.
  bool get peerPresent => seats.length >= 2;
  bool get everyoneHere => seats.length >= capacity;
  bool get usable => link == LinkState.live || link == LinkState.reconnecting;

  static String newCode() {
    // Unambiguous alphabet: no O/0, no I/1.
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(4, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  static SupabaseClient get _db => Supabase.instance.client;

  /// Register a new room so its code can be validated by whoever joins.
  /// Returns null on success, or why it failed.
  static Future<JoinError?> createRoom(String code, String hostId,
      {int capacity = 2}) async {
    if (!kOnlineEnabled) return JoinError.offline;
    try {
      await _db.from('rooms').insert({
        'code': code,
        'host_id': hostId,
        'status': 'waiting',
        'capacity': capacity.clamp(2, kMaxPlayers),
        'expires_at':
            DateTime.now().toUtc().add(kRoomTtl).toIso8601String(),
      });
      return null;
    } catch (e) {
      // Surface the cause — a swallowed error here looks to the player like
      // "no such table" when the room was never created in the first place.
      debugPrint('Pen Fight: createRoom failed for $code: $e');
      lastFailure = e.toString();
      return JoinError.unknown;
    }
  }

  /// Check a code before opening its channel, so a typo says "no such table"
  /// instead of silently dropping the player into an empty room.
  /// The seat [validateRoom] assigned on the most recent successful join.
  static int lastAssignedSeat = 1;

  static Future<JoinError?> validateRoom(String code, String guestId) async {
    if (!kOnlineEnabled) return JoinError.offline;
    try {
      final row = await _db
          .from('rooms')
          .select()
          .eq('code', code)
          .maybeSingle();

      if (row == null) return JoinError.noSuchRoom;

      final expires = DateTime.tryParse(row['expires_at'] as String? ?? '');
      if (expires != null && expires.isBefore(DateTime.now().toUtc())) {
        return JoinError.expired;
      }

      final capacity =
          ((row['capacity'] as num?)?.toInt() ?? 2).clamp(2, kMaxPlayers);

      // Seats are stored as a list of player ids, seat 0 being the host.
      final raw = (row['guests'] as List<dynamic>?) ?? const [];
      final guests = raw.map((e) => e.toString()).toList();

      // Re-joining your own seat after a refresh is always allowed.
      final existing = guests.indexOf(guestId);
      if (existing >= 0) {
        lastAssignedSeat = existing + 1;
        return null;
      }

      // The host holds seat 0, so there are capacity-1 guest seats.
      if (guests.length >= capacity - 1) return JoinError.roomFull;

      guests.add(guestId);
      lastAssignedSeat = guests.length; // seat 0 is the host

      await _db.from('rooms').update({
        'guests': guests,
        'guest_id': guests.first,
        'status': guests.length >= capacity - 1 ? 'playing' : 'waiting',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('code', code);
      return null;
    } catch (e) {
      debugPrint('Pen Fight: validateRoom failed for $code: $e');
      lastFailure = e.toString();
      return JoinError.unknown;
    }
  }

  /// Persist the settled state so a reconnecting player can resume.
  Future<void> saveState(List<Map<String, dynamic>> snapshot, int turn) async {
    if (!kOnlineEnabled) return;
    lastSnapshot = snapshot;
    lastTurn = turn;
    try {
      await _db.from('rooms').update({
        'state': {'pens': snapshot},
        'turn': turn,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('code', code);
    } catch (_) {
      // A failed save only costs resume-on-refresh; the live match is
      // driven by broadcast and keeps working.
    }
  }

  /// Pull the last saved state, for resuming after a reload.
  Future<void> loadState() async {
    if (!kOnlineEnabled) return;
    try {
      final row = await _db
          .from('rooms')
          .select('state, turn')
          .eq('code', code)
          .maybeSingle();
      final state = row?['state'] as Map<String, dynamic>?;
      final pens = state?['pens'] as List<dynamic>?;
      if (pens != null && pens.isNotEmpty) {
        lastSnapshot = pens;
        lastTurn = (row?['turn'] as num?)?.toInt() ?? 0;
        notifyListeners();
      }
    } catch (_) {
      // Resume is best-effort — fall back to a fresh table.
    }
  }

  Future<void> connect({required String name}) async {
    if (!kOnlineEnabled) {
      error = 'Supabase keys not configured';
      link = LinkState.dropped;
      notifyListeners();
      return;
    }

    final ch = _db.channel(
      'room:$code',
      opts: const RealtimeChannelConfig(self: false),
    );
    _channel = ch;

    ch
        .onPresenceSync((_) => _syncPresence(ch))
        .onPresenceJoin((_) => _syncPresence(ch))
        .onPresenceLeave((_) => _syncPresence(ch))
        .onBroadcast(event: 'flick', callback: _handleFlick)
        .onBroadcast(event: 'start', callback: (_) => onStart?.call())
        .onBroadcast(event: 'rematch', callback: (_) {
          peerForfeited = false;
          onPeerRematch?.call();
        })
        .subscribe((status, err) async {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              link = LinkState.live;
              error = null;
              await ch.track({'id': myId, 'seat': mySeat, 'name': name});
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
              // The client retries on its own; say so rather than freezing.
              link = LinkState.reconnecting;
              error = err?.toString();
            case RealtimeSubscribeStatus.closed:
              link = LinkState.dropped;
          }
          notifyListeners();
        });
  }

  void _handleFlick(Map<String, dynamic> payload) {
    final by = (payload['by'] as num).toInt();
    if (by == mySeat) return; // our own echo
    final gx = payload['gx'] as num?, gy = payload['gy'] as num?;
    final settled = payload['settled'] as List<dynamic>;
    final nextTurn = (payload['nextTurn'] as num).toInt();

    lastSnapshot = settled;
    lastTurn = nextTurn;

    onPeerFlick?.call(
      by,
      Vec2((payload['dx'] as num).toDouble(),
          (payload['dy'] as num).toDouble()),
      (payload['power'] as num).toDouble(),
      gx == null || gy == null ? null : Vec2(gx.toDouble(), gy.toDouble()),
      settled,
      nextTurn,
    );
  }

  void _syncPresence(RealtimeChannel ch) {
    final found = <Seat>[];
    for (final s in ch.presenceState()) {
      for (final p in s.presences) {
        final payload = p.payload;
        found.add(Seat(
          payload['id'] as String? ?? '?',
          (payload['seat'] as num?)?.toInt() ?? 0,
          payload['name'] as String? ?? 'PLAYER',
        ));
      }
    }
    found.sort((a, b) => a.index.compareTo(b.index));
    seats = found;

    if (peerPresent) {
      _peerEverSeen = true;
      _clearGrace();
    } else if (_peerEverSeen && !peerForfeited) {
      // Only start the clock on someone who was actually here — an empty
      // seat in the waiting room is not a disconnect.
      _startGrace();
    }
    notifyListeners();
  }

  void _startGrace() {
    if (_graceTimer != null) return; // already counting
    peerMissingFor = kPeerGrace;
    _graceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (peerMissingFor ?? Duration.zero) - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _clearGrace();
        peerForfeited = true;
        onPeerForfeit?.call();
      } else {
        peerMissingFor = left;
      }
      notifyListeners();
    });
  }

  void _clearGrace() {
    _graceTimer?.cancel();
    _graceTimer = null;
    peerMissingFor = null;
  }

  /// [nextTurn] is who acts after this shot. Sending it explicitly keeps the
  /// two clients in lockstep: whose turn it is is data, not something each
  /// side infers from its own animation finishing.
  Future<void> sendFlick(int seat, Vec2 dir, double power, Vec2? grab,
      List<Map<String, dynamic>> settled, int nextTurn) async {
    lastSnapshot = settled;
    lastTurn = nextTurn;
    await _send('flick', {
      'by': seat,
      'dx': dir.x,
      'dy': dir.y,
      'power': power,
      if (grab != null) 'gx': grab.x,
      if (grab != null) 'gy': grab.y,
      'settled': settled,
      'nextTurn': nextTurn,
    });
    // Persist after broadcasting so the live match never waits on the write.
    unawaited(saveState(settled, nextTurn));
  }

  Future<void> sendStart() => _send('start', {'at': _now});

  Future<void> sendRematch() {
    peerForfeited = false;
    return _send('rematch', {'at': _now});
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> _send(String event, Map<String, dynamic> payload) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: event, payload: payload);
    } catch (e) {
      // A send can fail mid-reconnect. Surface it rather than looking hung.
      link = LinkState.reconnecting;
      error = e.toString();
      notifyListeners();
    }
  }

  /// Mark the room finished so its code stops accepting joins.
  Future<void> closeRoom() async {
    if (!kOnlineEnabled) return;
    try {
      await _db.from('rooms').update({'status': 'done'}).eq('code', code);
    } catch (_) {
      // Expiry will collect it anyway.
    }
  }

  @override
  void dispose() {
    _clearGrace();
    final ch = _channel;
    _channel = null;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }
}
