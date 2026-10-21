import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.peerId});
  final String peerId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctl = TextEditingController();
  late final MeshService _mesh;

  @override
  void initState() {
    super.initState();
    _mesh = context.read<MeshService>();
    _mesh.openPeerId = widget.peerId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _mesh.markRead(widget.peerId));
  }

  @override
  void dispose() {
    _mesh.openPeerId = null;
    _ctl.dispose();
    super.dispose();
  }

  void _send() {
    final t = _ctl.text;
    if (t.trim().isEmpty) return;
    _ctl.clear();
    _mesh.sendText(widget.peerId, t); // queued instantly, delivered when the peer is in range
  }

  Future<void> _attach() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: C.surface,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 80);
    if (x != null) await _mesh.sendImage(widget.peerId, File(x.path));
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    final peer = mesh.peers[widget.peerId];
    if (peer == null) return const Scaffold(body: Center(child: Text('Peer removed')));
    final msgs = mesh.thread(peer.id);
    if (mesh.unread(peer.id) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mesh.markRead(peer.id));
    }
    final (statusText, statusColor) = peer.online
        ? ('Active now', C.online)
        : peer.connecting
            ? ('Connecting…', C.indigoSoft)
            : peer.discovered
                ? ('In range', C.indigoSoft)
                : ('Offline', C.muted);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          PeerAvatar(name: peer.name, color: peer.color, online: peer.online, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(statusText, style: TextStyle(fontSize: 12.5, color: statusColor)),
            ]),
          ),
        ]),
      ),
      body: Column(children: [
        if (!peer.online)
          Container(
            width: double.infinity,
            color: C.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Out of range. Messages wait in the queue and are delivered automatically when this peer reconnects.',
              style: TextStyle(fontSize: 12.5, color: C.muted)),
          ),
        Expanded(
          child: msgs.isEmpty
              ? const Center(child: Text('No messages yet', style: TextStyle(color: C.muted)))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[msgs.length - 1 - i];
                    return _Bubble(m: m);
                  },
                ),
        ),
        _InputBar(ctl: _ctl, onSend: _send, onAttach: _attach),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m});
  final Message m;

  @override
  Widget build(BuildContext context) {
    final out = m.outgoing;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
        decoration: BoxDecoration(
          color: out ? null : C.surface2,
          gradient: out
              ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)])
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(out ? 18 : 4), bottomRight: Radius.circular(out ? 4 : 18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (m.type == 'image' && m.path != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog.fullscreen(
                    backgroundColor: Colors.black,
                    child: Stack(children: [
                      Center(child: InteractiveViewer(child: Image.file(File(m.path!)))),
                      SafeArea(child: IconButton(
                          icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
                    ]),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(m.path!), width: 230, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                          width: 230, height: 120, child: Icon(Icons.broken_image, color: C.muted))),
                ),
              ),
            ),
          if (m.body.isNotEmpty)
            Align(alignment: Alignment.centerLeft,
                child: Text(m.body, style: const TextStyle(fontSize: 15.5, height: 1.3))),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (out && m.status == MsgStatus.queued)
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Text('Sending…', style: TextStyle(fontSize: 11, color: Colors.white70))),
            Text(hm(m.ts),
                style: TextStyle(fontSize: 11, color: out ? Colors.white70 : C.muted)),
            if (out) ...[const SizedBox(width: 4), Ticks(m.status)],
          ]),
        ]),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.ctl, required this.onSend, required this.onAttach});
  final TextEditingController ctl;
  final VoidCallback onSend, onAttach;

  @override
  Widget build(BuildContext context) => Container(
        color: C.surface,
        padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom * 0),
        child: SafeArea(
          top: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(onPressed: onAttach, icon: const Icon(Icons.attach_file, color: C.muted)),
            Expanded(
              child: TextField(
                controller: ctl, minLines: 1, maxLines: 5, maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  counterText: '', hintText: 'Message', filled: true, fillColor: C.bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: C.indigo, shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(), onTap: onSend,
                child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.send_rounded, size: 22))),
            ),
          ]),
        ),
      );
}
