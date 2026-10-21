import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'mesh_service.dart';
import 'models.dart';
import 'theme.dart';

String hm(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Gradient avatar with an optional presence dot (green = in range & connected).
class PeerAvatar extends StatelessWidget {
  const PeerAvatar({super.key, required this.name, required this.color, this.online, this.size = 46});
  final String name;
  final int color;
  final bool? online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = C.avatar(color);
    final dot = size * .28;
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size, height: size, alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [c, Color.lerp(c, Colors.black, .38)!]),
        ),
        child: Text(
          name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase(),
          style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      if (online != null)
        Positioned(
          right: -1, bottom: -1,
          child: Container(
            width: dot, height: dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online! ? C.online : C.muted.withOpacity(.55),
              border: Border.all(color: C.bg, width: 2.5),
            ),
          ),
        ),
    ]);
  }
}

/// Delivery state: clock = queued, one tick = handed to peer link, two ticks = acked.
class Ticks extends StatelessWidget {
  const Ticks(this.s, {super.key});
  final MsgStatus s;
  @override
  Widget build(BuildContext context) => switch (s) {
        MsgStatus.queued => const Icon(Icons.schedule, size: 14, color: Colors.white70),
        MsgStatus.sent => const Icon(Icons.done, size: 15, color: Colors.white70),
        MsgStatus.delivered => const Icon(Icons.done_all, size: 15, color: Color(0xFFC7D2FE)),
      };
}

/// Link quality from round-trip latency (Nearby Connections exposes no RSSI/dBm).
class LinkBars extends StatelessWidget {
  const LinkBars({super.key, required this.rtt, this.active = true});
  final int? rtt;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final n = !active || rtt == null ? 0 : rtt! < 60 ? 4 : rtt! < 120 ? 3 : rtt! < 250 ? 2 : 1;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 1; i <= 4; i++)
        Container(
          width: 4, height: 4.0 + i * 3, margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: i <= n ? C.online : C.line, borderRadius: BorderRadius.circular(1.5)),
        ),
    ]);
  }
}

/// Shows startup problems (permissions / Bluetooth) with one-tap recovery.
class MeshBanner extends StatelessWidget {
  const MeshBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    if (mesh.error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B1D2A), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7F1D3A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bluetooth_disabled, size: 18, color: Color(0xFFFCA5A5)),
          const SizedBox(width: 8),
          Expanded(child: Text(mesh.error!, style: const TextStyle(fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(onPressed: mesh.start, child: const Text('Retry')),
          TextButton(onPressed: openAppSettings, child: const Text('App settings')),
        ]),
      ]),
    );
  }
}

/// Header pill: live mesh state.
class MeshChip extends StatelessWidget {
  const MeshChip({super.key});
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MeshService>();
    final (color, text) = !m.running
        ? (C.muted, 'Mesh off')
        : m.onlineCount > 0
            ? (C.online, '${m.onlineCount} connected')
            : (C.indigoSoft, 'Searching…');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.14), borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
