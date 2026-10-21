import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// SQLite storage: peer mappings + full chat history (including the offline queue,
/// which is simply every outgoing message whose status is not "delivered").
class Db {
  late Database _db;

  Future<void> open() async {
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'pulsemesh.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE peers('
            'id TEXT PRIMARY KEY, name TEXT NOT NULL, color INTEGER NOT NULL, last_seen INTEGER NOT NULL)');
        await d.execute('CREATE TABLE messages('
            'id TEXT PRIMARY KEY, peer_id TEXT NOT NULL, outgoing INTEGER NOT NULL, type TEXT NOT NULL, '
            'body TEXT NOT NULL, path TEXT, ts INTEGER NOT NULL, status INTEGER NOT NULL, is_read INTEGER NOT NULL)');
        await d.execute('CREATE INDEX idx_msg_peer ON messages(peer_id, ts)');
      },
    );
  }

  Future<List<Peer>> peers() async =>
      (await _db.query('peers')).map(Peer.fromMap).toList();

  Future<void> upsertPeer(Peer x) =>
      _db.insert('peers', x.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Message>> messages() async =>
      (await _db.query('messages', orderBy: 'ts ASC')).map(Message.fromMap).toList();

  Future<void> insertMessage(Message m) =>
      _db.insert('messages', m.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> setStatus(String id, MsgStatus s) =>
      _db.update('messages', {'status': s.index}, where: 'id = ?', whereArgs: [id]);

  Future<void> markRead(String peerId) => _db.update('messages', {'is_read': 1},
      where: 'peer_id = ? AND outgoing = 0', whereArgs: [peerId]);

  Future<void> clearAll() async {
    await _db.delete('messages');
    await _db.delete('peers');
  }
}
