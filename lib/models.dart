enum MsgStatus { queued, sent, delivered }

class Peer {
  Peer({required this.id, required this.name, required this.color, this.lastSeen = 0});

  final String id; // stable 8-char device id (survives Nearby endpoint rotation)
  String name;
  int color;
  int lastSeen;

  // runtime-only state
  String? endpointId;
  bool online = false;
  bool discovered = false;
  bool connecting = false;
  int? rtt; // round-trip ms, measured by ping/pong

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'color': color, 'last_seen': lastSeen};

  factory Peer.fromMap(Map<String, Object?> m) => Peer(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as int,
        lastSeen: m['last_seen'] as int,
      );
}

class Message {
  Message({
    required this.id,
    required this.peerId,
    required this.outgoing,
    required this.type, // 'text' | 'image'
    required this.body,
    this.path,
    required this.ts,
    this.status = MsgStatus.queued,
    this.read = true,
  });

  final String id, peerId, type, body;
  final String? path;
  final bool outgoing;
  final int ts;
  MsgStatus status;
  bool read;

  Map<String, Object?> toMap() => {
        'id': id, 'peer_id': peerId, 'outgoing': outgoing ? 1 : 0, 'type': type,
        'body': body, 'path': path, 'ts': ts, 'status': status.index, 'is_read': read ? 1 : 0,
      };

  factory Message.fromMap(Map<String, Object?> m) => Message(
        id: m['id'] as String,
        peerId: m['peer_id'] as String,
        outgoing: (m['outgoing'] as int) == 1,
        type: m['type'] as String,
        body: m['body'] as String,
        path: m['path'] as String?,
        ts: m['ts'] as int,
        status: MsgStatus.values[m['status'] as int],
        read: (m['is_read'] as int) == 1,
      );
}
