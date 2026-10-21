import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'models.dart';

class _Found {
  _Found(this.endpointId, this.peerId) : since = DateTime.now();
  final String endpointId, peerId;
  final DateTime since;
}

/// Core engine: permissions, Bluetooth, foreground service, Nearby Connections
/// (P2P_CLUSTER), presence, offline queue, delivery acks, media transfer.
///
/// Wire format: every control/text message is one JSON object sent as a Nearby
/// BYTES payload (<= 32 KB). Images travel as FILE payloads plus a small JSON
/// "meta" envelope that carries the payload id, file name and caption.
///   {t:'m', id, ts, x}            text message
///   {t:'i', id, ts, pid, n, x}    image meta (file payload id = pid)
///   {t:'a', id}                   delivery ack
///   {t:'p', ts} / {t:'o', ts}     ping / pong (link latency)
///   {t:'n', x, c}                 profile update (name, color)
class MeshService extends ChangeNotifier {
  static const _native = MethodChannel('pulsemesh/native');
  static const serviceId = 'com.pulsemesh.mesh';
  static const _uuid = Uuid();

  final Db db = Db();
  final Nearby _nearby = Nearby();
  late SharedPreferences _prefs;
  late String _mediaDir;

  // ---- identity & settings
  late String myId;
  String myName = '';
  int myColor = 0;
  bool autoBluetooth = true;

  // ---- engine state
  bool wantRunning = true, running = false, _starting = false, _btDropped = false;
  String? error;
  String? openPeerId; // chat currently on screen
  Timer? _timer;
  String _lastServiceText = '';

  // ---- data
  final Map<String, Peer> peers = {};
  final Map<String, List<Message>> _threads = {};
  final Set<String> _ids = {};

  // ---- transport bookkeeping
  final Map<String, String> _epToPeer = {}; // endpointId -> peerId
  final Map<String, _Found> _found = {};
  final Set<String> _pending = {};
  final Set<String> _flushing = {};
  final Map<int, String> _filePaths = {};
  final Set<int> _fileDone = {};
  final Map<int, Map<String, dynamic>> _imgMeta = {};

  // ======================================================== lifecycle
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    myId = _prefs.getString('id') ?? _uuid.v4().substring(0, 8);
    await _prefs.setString('id', myId);
    myName = _prefs.getString('name') ?? 'Node-${myId.substring(0, 4)}';
    myColor = _prefs.getInt('color') ?? (myId.codeUnitAt(0) % 8);
    autoBluetooth = _prefs.getBool('auto_bt') ?? true;
    wantRunning = _prefs.getBool('mesh_on') ?? true;

    final docs = await getApplicationDocumentsDirectory();
    _mediaDir = p.join(docs.path, 'media');
    await Directory(_mediaDir).create(recursive: true);

    await db.open();
    for (final pr in await db.peers()) {
      peers[pr.id] = pr;
    }
    for (final m in await db.messages()) {
      (_threads[m.peerId] ??= []).add(m);
      _ids.add(m.id);
    }
  }


  /// Permissions -> Bluetooth -> foreground service -> advertise + discover.
  Future<void> start() async {
    wantRunning = true;
    await _prefs.setBool('mesh_on', true);
    if (running || _starting) return;
    _starting = true;
    error = null;
    notifyListeners();
    try {
      if (!await _ensurePermissions()) {
        error = 'PulseMesh needs Bluetooth, Nearby devices and notification permissions.';
        return;
      }
      if (!await _ensureBluetooth()) return;
      await _native.invokeMethod('startService', {'text': _serviceText()});
      await _startNearby();
      running = true;
      _btDropped = false;
      _timer ??= Timer.periodic(const Duration(seconds: 8), (_) => _maintenance());
    } catch (e) {
      error = 'Could not start the mesh: $e';
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    wantRunning = false;
    await _prefs.setBool('mesh_on', false);
    await _stopNearby();
    running = false;
    _lastServiceText = '';
    await _safe(() => _native.invokeMethod('stopService'));
    notifyListeners();
  }

  /// Called when the app returns to the foreground.
  Future<void> onResume() async {
    if (!wantRunning) return;
    if (!running) {
      await start();
    } else if (!(await _btOn())) {
      await _maintenance();
    }
  }

  Future<bool> _ensurePermissions() async {
    final sdk = await _native.invokeMethod<int>('sdkInt') ?? 0;
    final req = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.notification,
      if (sdk <= 32) Permission.locationWhenInUse, // ACCESS_FINE_LOCATION (<= Android 12L)
      if (sdk >= 33) Permission.nearbyWifiDevices,
    ];
    final res = await req.request();
    return res.entries
        .where((e) => e.key != Permission.notification) // service still runs without it
        .every((e) => e.value.isGranted || e.value.isLimited);
  }

  Future<bool> _btOn() async => await _native.invokeMethod<bool>('isBluetoothOn') ?? false;

  Future<bool> _ensureBluetooth() async {
    if (await _btOn()) return true;
    if (!autoBluetooth) {
      error = 'Bluetooth is off. Turn it on, or enable Auto-Bluetooth in Settings.';
      return false;
    }
    // Android shows a system dialog; apps cannot flip Bluetooth silently on 13+.
    final ok = await _native.invokeMethod<bool>('requestEnableBluetooth') ?? false;
    if (!ok) error = 'Bluetooth must be on for PulseMesh to find nearby peers.';
    return ok;
  }

  Future<void> _maintenance() async {
    final bt = await _btOn();
    if (running && !bt) {
      await _stopNearby();
      running = false;
      _btDropped = true;
      error = 'Bluetooth turned off. PulseMesh resumes when it is back on.';
      notifyListeners();
      return;
    }
    if (!running && _btDropped && wantRunning && bt && !_starting) {
      await start();
      return;
    }
    if (!running) return;

    final now = DateTime.now();
    // (Re)connect to discovered peers. The lower id initiates; the other side
    // falls back after 30 s so one-sided discovery still links up.
    for (final f in _found.values.toList()) {
      final pr = peers[f.peerId];
      if (pr == null || pr.online || _pending.contains(f.endpointId)) continue;
      if (myId.compareTo(f.peerId) < 0 || now.difference(f.since).inSeconds > 30) _request(f);
    }
    // Latency probe doubles as keep-alive.
    for (final pr in peers.values.where((x) => x.online && x.endpointId != null)) {
      _safe(() => _send(pr.endpointId!, {'t': 'p', 'ts': now.millisecondsSinceEpoch}));
    }
    _updateService();
  }

  // ======================================================== Nearby: advertise + discover
  String get _nick => '${myName.replaceAll('|', '')}|$myId|$myColor';

  ({String name, String id, int color})? _parse(String s) {
    final a = s.split('|');
    if (a.length != 3 || a[1].length != 8) return null; // not a PulseMesh node
    return (name: a[0].isEmpty ? 'Unknown' : a[0], id: a[1], color: int.tryParse(a[2]) ?? 0);
  }

  Future<void> _startNearby() async {
    try {
      await _nearby.startAdvertising(_nick, Strategy.P2P_CLUSTER,
          onConnectionInitiated: _onInit,
          onConnectionResult: _onResult,
          onDisconnected: _onDisc,
          serviceId: serviceId);
    } on PlatformException catch (e) {
      if (!'${e.code} ${e.message}'.contains('ALREADY')) rethrow;
    }
    try {
      await _nearby.startDiscovery(_nick, Strategy.P2P_CLUSTER,
          onEndpointFound: _onFound, onEndpointLost: _onLost, serviceId: serviceId);
    } on PlatformException catch (e) {
      if (!'${e.code} ${e.message}'.contains('ALREADY')) rethrow;
    }
  }

  Future<void> _stopNearby() async {
    await _safe(() => _nearby.stopAdvertising());
    await _safe(() => _nearby.stopDiscovery());
    await _safe(() => _nearby.stopAllEndpoints());
    for (final pr in peers.values) {
      pr.online = pr.connecting = pr.discovered = false;
      pr.endpointId = null;
      pr.rtt = null;
    }
    _epToPeer.clear();
    _found.clear();
    _pending.clear();
  }

  Peer _upsert(({String name, String id, int color}) i) {
    var pr = peers[i.id];
    if (pr == null) {
      pr = Peer(id: i.id, name: i.name, color: i.color);
      peers[i.id] = pr;
    } else {
      pr.name = i.name;
      pr.color = i.color;
    }
    _safe(() => db.upsertPeer(pr!));
    return pr;
  }

  void _onFound(String id, String name, String svc) {
    final info = _parse(name);
    if (info == null || info.id == myId) return;
    final pr = _upsert(info)..discovered = true;
    final f = _Found(id, info.id);
    _found[id] = f;
    notifyListeners();
    if (!pr.online && myId.compareTo(info.id) < 0) _request(f);
  }

  void _onLost(String? id) {
    final f = _found.remove(id);
    final pr = f == null ? null : peers[f.peerId];
    if (pr != null && !pr.online) pr.discovered = false;
    notifyListeners();
  }

  void connectTo(String peerId) {
    for (final f in _found.values) {
      if (f.peerId == peerId) _request(f);
    }
  }

  Future<void> _request(_Found f) async {
    final pr = peers[f.peerId];
    if (pr == null || pr.online || _pending.contains(f.endpointId)) return;
    _pending.add(f.endpointId);
    pr.connecting = true;
    notifyListeners();
    try {
      await _nearby.requestConnection(_nick, f.endpointId,
          onConnectionInitiated: _onInit, onConnectionResult: _onResult, onDisconnected: _onDisc);
    } catch (_) {
      _pending.remove(f.endpointId);
      pr.connecting = false;
      notifyListeners();
    }
  }

  // Connection handshake. Nearby encrypts the link; we auto-accept other PulseMesh nodes.
  void _onInit(String id, ConnectionInfo info) {
    final pi = _parse(info.endpointName);
    if (pi == null || pi.id == myId) {
      _safe(() => _nearby.rejectConnection(id));
      return;
    }
    _epToPeer[id] = pi.id;
    _upsert(pi).connecting = true;
    notifyListeners();
    _safe(() => _nearby.acceptConnection(id,
        onPayLoadRecieved: (eid, payload) => _onPayload(eid, payload),
        onPayloadTransferUpdate: (eid, u) => _onTransfer(eid, u)));
  }

  void _onResult(String id, Status s) {
    _pending.remove(id);
    final pr = peers[_epToPeer[id]];
    if (pr == null) return;
    pr.connecting = false;
    if (s == Status.CONNECTED) {
      if (pr.online && pr.endpointId != id) {
        // duplicate link (both sides dialled at once): keep the first one
        _safe(() => _nearby.disconnectFromEndpoint(id));
        _epToPeer.remove(id);
        return;
      }
      pr
        ..online = true
        ..endpointId = id
        ..lastSeen = DateTime.now().millisecondsSinceEpoch;
      _safe(() => db.upsertPeer(pr));
      _safe(() => _send(id, {'t': 'p', 'ts': DateTime.now().millisecondsSinceEpoch}));
      _flush(pr.id, resend: true); // offline queue: deliver everything not yet acked
    } else {
      _epToPeer.remove(id);
    }
    notifyListeners();
    _updateService();
  }

  void _onDisc(String id) {
    _pending.remove(id);
    final pid = _epToPeer.remove(id);
    final pr = pid == null ? null : peers[pid];
    if (pr != null && pr.endpointId == id) {
      pr
        ..online = false
        ..connecting = false
        ..endpointId = null
        ..rtt = null;
    }
    notifyListeners();
    _updateService();
  }

  // ======================================================== receive
  void _onPayload(String eid, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final peerId = _epToPeer[eid];
      if (peerId == null) return;
      try {
        final j = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
        _handle(eid, peerId, j);
      } catch (_) {/* ignore malformed frames */}
    } else if (payload.type == PayloadType.FILE && payload.filePath != null) {
      _filePaths[payload.id] = payload.filePath!; // finalised once transfer succeeds
    }
  }

  void _onTransfer(String eid, PayloadTransferUpdate u) {
    if (u.status == PayloadStatus.SUCCESS && _filePaths.containsKey(u.id)) {
      _fileDone.add(u.id);
      _tryFinishImage(u.id);
    }
  }

  Future<void> _handle(String eid, String peerId, Map<String, dynamic> j) async {
    final pr = peers[peerId];
    switch (j['t']) {
      case 'm':
        final id = j['id'] as String;
        if (!_ids.contains(id)) {
          var text = (j['x'] as String? ?? '');
          if (text.length > 4000) text = text.substring(0, 4000);
          await _add(Message(
              id: id, peerId: peerId, outgoing: false, type: 'text', body: text,
              ts: DateTime.now().millisecondsSinceEpoch,
              status: MsgStatus.delivered, read: openPeerId == peerId));
        }
        _safe(() => _send(eid, {'t': 'a', 'id': id})); // always ack (sender may have retried)
      case 'i':
        final pid = j['pid'] as int;
        _imgMeta[pid] = {...j, '_peer': peerId, '_eid': eid};
        _tryFinishImage(pid);
      case 'a':
        for (final m in thread(peerId)) {
          if (m.id == j['id'] && m.outgoing && m.status != MsgStatus.delivered) {
            m.status = MsgStatus.delivered;
            _safe(() => db.setStatus(m.id, MsgStatus.delivered));
          }
        }
        notifyListeners();
      case 'p':
        _safe(() => _send(eid, {'t': 'o', 'ts': j['ts']}));
      case 'o':
        if (pr != null) {
          pr.rtt = DateTime.now().millisecondsSinceEpoch - (j['ts'] as int);
          notifyListeners();
        }
      case 'n':
        if (pr != null) {
          final n = (j['x'] as String? ?? '').trim();
          if (n.isNotEmpty) pr.name = n.length > 24 ? n.substring(0, 24) : n;
          pr.color = (j['c'] as int?) ?? pr.color;
          _safe(() => db.upsertPeer(pr));
          notifyListeners();
        }
    }
  }

  String _clean(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<void> _tryFinishImage(int pid) async {
    final meta = _imgMeta[pid], src = _filePaths[pid];
    if (meta == null || src == null || !_fileDone.contains(pid)) return;
    _imgMeta.remove(pid);
    _filePaths.remove(pid);
    _fileDone.remove(pid);
    final peerId = meta['_peer'] as String, eid = meta['_eid'] as String;
    final id = meta['id'] as String;
    if (!_ids.contains(id)) {
      // never trust a remote file name: sanitise before touching the filesystem
      final dest = p.join(_mediaDir, '${_clean(id)}_${_clean(p.basename(meta['n'] as String))}');
      try {
        await File(src).copy(dest);
        await _safe(() => File(src).delete());
      } catch (_) {
        return; // unreadable: no ack, so the sender retries on the next link
      }
      var cap = (meta['x'] as String? ?? '');
      if (cap.length > 1000) cap = cap.substring(0, 1000);
      await _add(Message(
          id: id, peerId: peerId, outgoing: false, type: 'image', body: cap, path: dest,
          ts: DateTime.now().millisecondsSinceEpoch,
          status: MsgStatus.delivered, read: openPeerId == peerId));
    }
    _safe(() => _send(eid, {'t': 'a', 'id': id}));
  }

  // ======================================================== send + offline queue
  Future<void> _send(String eid, Map<String, dynamic> j) =>
      _nearby.sendBytesPayload(eid, Uint8List.fromList(utf8.encode(jsonEncode(j))));

  Future<void> sendText(String peerId, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final m = Message(
        id: _uuid.v4(), peerId: peerId, outgoing: true, type: 'text', body: t,
        ts: DateTime.now().millisecondsSinceEpoch); // starts as "Sending…"
    await _add(m);
    _flush(peerId);
  }

  Future<void> sendImage(String peerId, File src, {String caption = ''}) async {
    final id = _uuid.v4();
    final dest = p.join(_mediaDir, '${id}_${_clean(p.basename(src.path))}');
    await src.copy(dest); // keep our own copy so queued media survives
    await _add(Message(
        id: id, peerId: peerId, outgoing: true, type: 'image', body: caption, path: dest,
        ts: DateTime.now().millisecondsSinceEpoch));
    _flush(peerId);
  }

  /// Delivers queued messages in order. [resend] also retries "sent but not yet
  /// acked" messages after a reconnect; receivers de-duplicate by message id.
  Future<void> _flush(String peerId, {bool resend = false}) async {
    if (!_flushing.add(peerId)) return;
    try {
      for (final m in List<Message>.of(thread(peerId))) {
        if (!m.outgoing || m.status == MsgStatus.delivered) continue;
        if (m.status == MsgStatus.sent && !resend) continue;
        final pr = peers[peerId];
        if (pr == null || !pr.online || pr.endpointId == null) break; // stay queued
        try {
          final eid = pr.endpointId!;
          if (m.type == 'text') {
            await _send(eid, {'t': 'm', 'id': m.id, 'ts': m.ts, 'x': m.body});
          } else {
            final pid = await _nearby.sendFilePayload(eid, m.path!);
            await _send(eid, {'t': 'i', 'id': m.id, 'ts': m.ts, 'pid': pid, 'n': p.basename(m.path!), 'x': m.body});
          }
          if (m.status == MsgStatus.queued) {
            m.status = MsgStatus.sent;
            await db.setStatus(m.id, MsgStatus.sent);
          }
          notifyListeners();
        } catch (_) {
          break; // link dropped mid-send: remaining messages stay queued
        }
      }
    } finally {
      _flushing.remove(peerId);
    }
  }

  // ======================================================== data access
  List<Message> thread(String peerId) => _threads[peerId] ?? const [];
  Message? lastMessage(String peerId) {
    final t = thread(peerId);
    return t.isEmpty ? null : t.last;
  }

  int unread(String peerId) => thread(peerId).where((m) => !m.outgoing && !m.read).length;
  int get unreadTotal => _threads.keys.fold(0, (a, k) => a + unread(k));
  int get onlineCount => peers.values.where((x) => x.online).length;

  Future<void> _add(Message m) async {
    (_threads[m.peerId] ??= []).add(m);
    _ids.add(m.id);
    await db.insertMessage(m);
    notifyListeners();
    _updateService();
  }

  Future<void> markRead(String peerId) async {
    var changed = false;
    for (final m in thread(peerId)) {
      if (!m.outgoing && !m.read) {
        m.read = true;
        changed = true;
      }
    }
    if (changed) {
      await db.markRead(peerId);
      notifyListeners();
      _updateService();
    }
  }

  // ======================================================== settings
  Future<void> setName(String n) async {
    final t = n.trim();
    if (t.isEmpty) return;
    myName = t.length > 24 ? t.substring(0, 24) : t;
    await _prefs.setString('name', myName);
    await _profileChanged();
  }

  Future<void> setColor(int c) async {
    myColor = c;
    await _prefs.setInt('color', c);
    await _profileChanged();
  }

  Future<void> _profileChanged() async {
    for (final pr in peers.values.where((x) => x.online && x.endpointId != null)) {
      _safe(() => _send(pr.endpointId!, {'t': 'n', 'x': myName, 'c': myColor}));
    }
    if (running) {
      await _safe(() => _nearby.stopAdvertising()); // refresh the advertised nickname
      await _safe(() => _nearby.startAdvertising(_nick, Strategy.P2P_CLUSTER,
          onConnectionInitiated: _onInit, onConnectionResult: _onResult,
          onDisconnected: _onDisc, serviceId: serviceId));
    }
    notifyListeners();
  }

  Future<void> setAutoBluetooth(bool v) async {
    autoBluetooth = v;
    await _prefs.setBool('auto_bt', v);
    notifyListeners();
    if (v && wantRunning && !running) start();
  }

  /// Local database cleaner: wipes chats, media and offline peers (keeps live links).
  Future<void> clearHistory() async {
    await db.clearAll();
    _threads.clear();
    _ids.clear();
    final dir = Directory(_mediaDir);
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        await _safe(() => f.delete(recursive: true));
      }
    }
    peers.removeWhere((_, x) => !x.online && !x.discovered);
    for (final x in peers.values) {
      await db.upsertPeer(x);
    }
    notifyListeners();
    _updateService();
  }

  // ======================================================== helpers
  String _serviceText() => '$onlineCount connected · $unreadTotal unread';

  void _updateService() {
    if (!running) return;
    final t = _serviceText();
    if (t == _lastServiceText) return;
    _lastServiceText = t;
    _safe(() => _native.invokeMethod('startService', {'text': t}));
  }

  Future<void> _safe(Future<dynamic> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
