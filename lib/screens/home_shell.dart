import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'radar_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Startup: ask permissions, prompt for Bluetooth, start service + discovery. No taps needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mesh = context.read<MeshService>();
      if (mesh.wantRunning) mesh.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.select<MeshService, int>((m) => m.unreadTotal);
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: [
          ChatsTab(onGoRadar: () => setState(() => _tab = 1)),
          const RadarTab(),
          const SettingsTab(),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'),
                child: const Icon(Icons.forum_outlined)),
            selectedIcon: const Icon(Icons.forum, color: C.indigoSoft),
            label: 'Chats'),
          const NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar, color: C.indigoSoft), label: 'Radar'),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: C.indigoSoft), label: 'Profile'),
        ],
      ),
    );
  }
}

// ============================================================ Tab 1: Chats
class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key, required this.onGoRadar});
  final VoidCallback onGoRadar;

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    final list = mesh.peers.values
        .where((p) => mesh.thread(p.id).isNotEmpty || p.online)
        .toList()
      ..sort((a, b) => (mesh.lastMessage(b.id)?.ts ?? b.lastSeen)
          .compareTo(mesh.lastMessage(a.id)?.ts ?? a.lastSeen));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
        child: Row(children: [
          const Expanded(
            child: Text('PulseMesh',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.5))),
          const MeshChip(),
        ]),
      ),
      const MeshBanner(),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 84, height: 84,
                      decoration: const BoxDecoration(color: C.surface, shape: BoxShape.circle),
                      child: const Icon(Icons.hub_outlined, size: 40, color: C.indigoSoft)),
                    const SizedBox(height: 16),
                    const Text('No conversations yet',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('Nearby PulseMesh users connect automatically.\nOpen Radar to see who is in range.',
                        textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onGoRadar, icon: const Icon(Icons.radar), label: const Text('Open Radar')),
                  ]),
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _ChatTile(peer: list[i]),
              ),
      ),
    ]);
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.peer});
  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    final last = mesh.lastMessage(peer.id);
    final unread = mesh.unread(peer.id);
    return InkWell(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: peer.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          PeerAvatar(name: peer.name, color: peer.color, online: peer.online, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(peer.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Row(children: [
                if (last != null && last.outgoing) ...[
                  Ticks(last.status), const SizedBox(width: 4)],
                if (last?.type == 'image') ...[
                  const Icon(Icons.photo, size: 15, color: C.muted), const SizedBox(width: 4)],
                Expanded(
                  child: Text(
                    last == null
                        ? (peer.online ? 'Connected — say hello' : 'Offline')
                        : (last.body.isEmpty && last.type == 'image' ? 'Photo' : last.body),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: C.muted, fontSize: 13.5)),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(last == null ? '' : hm(last.ts),
                style: TextStyle(fontSize: 12, color: unread > 0 ? C.indigoSoft : C.muted)),
            const SizedBox(height: 6),
            if (unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: C.indigo, borderRadius: BorderRadius.circular(99)),
                child: Text('$unread',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
            else
              const SizedBox(height: 20),
          ]),
        ]),
      ),
    );
  }
}
