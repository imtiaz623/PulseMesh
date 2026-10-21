import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';

// ============================================================ Tab 2: Radar
class RadarTab extends StatefulWidget {
  const RadarTab({super.key});
  @override
  State<RadarTab> createState() => _RadarTabState();
}

class _RadarTabState extends State<RadarTab> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  // Distance from centre: connected peers by measured latency, discovered-only on the outer ring.
  double _frac(Peer p) {
    if (!p.online) return .9;
    final r = p.rtt;
    if (r == null) return .6;
    return r < 60 ? .3 : r < 120 ? .5 : r < 250 ? .68 : .8;
  }

  double _angle(String id) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return (h % 360) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    final nodes = mesh.peers.values.where((p) => p.online || p.discovered || p.connecting).toList()
      ..sort((a, b) => (b.online ? 1 : 0).compareTo(a.online ? 1 : 0));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
        child: Row(children: [
          const Expanded(
            child: Text('Radar',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.5))),
          const MeshChip(),
        ]),
      ),
      const MeshBanner(),
      Expanded(
        flex: 5,
        child: LayoutBuilder(builder: (_, box) {
          final s = math.min(box.maxWidth, box.maxHeight) - 8;
          final c = s / 2, maxR = c - 26;
          return Center(
            child: SizedBox(
              width: s, height: s,
              child: Stack(children: [
                AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, __) => CustomPaint(
                      size: Size(s, s), painter: _RadarPainter(_sweep.value, mesh.running)),
                ),
                Positioned(
                  left: c - 24, top: c - 24,
                  child: PeerAvatar(name: mesh.myName, color: mesh.myColor, size: 48)),
                for (final p in nodes)
                  Positioned(
                    left: c + math.cos(_angle(p.id)) * _frac(p) * maxR - 21,
                    top: c + math.sin(_angle(p.id)) * _frac(p) * maxR - 21,
                    child: GestureDetector(
                      onTap: () => _sheet(context, p),
                      child: Opacity(
                        opacity: p.online ? 1 : .6,
                        child: PeerAvatar(name: p.name, color: p.color, online: p.online, size: 42)),
                    ),
                  ),
              ]),
            ),
          );
        }),
      ),
      Expanded(
        flex: 4,
        child: Container(
          decoration: const BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text('Nearby nodes · ${nodes.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Expanded(
              child: nodes.isEmpty
                  ? Center(
                      child: Text(mesh.running ? 'Scanning for PulseMesh users…' : 'Mesh is off',
                          style: const TextStyle(color: C.muted)))
                  : ListView.builder(
                      itemCount: nodes.length,
                      itemBuilder: (_, i) => _NodeRow(p: nodes[i], onTap: () => _sheet(context, nodes[i])),
                    ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Distance rings show link latency. Android Nearby does not expose raw dBm.',
                style: TextStyle(fontSize: 11.5, color: C.muted))),
          ]),
        ),
      ),
    ]);
  }

  void _sheet(BuildContext context, Peer p) {
    final mesh = context.read<MeshService>();
    showModalBottomSheet(
      context: context,
      backgroundColor: C.surface,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PeerAvatar(name: p.name, color: p.color, online: p.online, size: 72),
          const SizedBox(height: 12),
          Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(_state(p), style: const TextStyle(color: C.muted)),
          Text('ID ${p.id}', style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 18),
          Row(children: [
            if (!p.online && p.discovered && !p.connecting)
              Expanded(
                child: OutlinedButton(
                  onPressed: () { mesh.connectTo(p.id); Navigator.pop(sheetCtx); },
                  child: const Text('Connect'))),
            if (!p.online && p.discovered && !p.connecting) const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: p.id)));
                },
                child: const Text('Open chat'))),
          ]),
        ]),
      ),
    );
  }

  String _state(Peer p) => p.online
      ? 'Connected${p.rtt == null ? '' : ' · ${p.rtt} ms'}'
      : p.connecting ? 'Connecting…' : 'In range · not connected';
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.p, required this.onTap});
  final Peer p;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: PeerAvatar(name: p.name, color: p.color, online: p.online, size: 40),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          p.online ? 'Connected${p.rtt == null ? '' : ' · ${p.rtt} ms'}'
              : p.connecting ? 'Connecting…' : 'In range',
          style: const TextStyle(color: C.muted, fontSize: 13)),
        trailing: LinkBars(rtt: p.rtt, active: p.online),
      );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.active);
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r,
        Paint()..shader = RadialGradient(colors: [C.indigo.withOpacity(.16), Colors.transparent]).createShader(Rect.fromCircle(center: c, radius: r)));
    final ring = Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = C.line;
    for (final f in [.33, .66, 1.0]) {
      canvas.drawCircle(c, r * f - 1, ring);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), ring);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), ring);
    if (!active) return;
    // rotating sweep
    canvas.drawCircle(c, r,
        Paint()..shader = SweepGradient(
          colors: [Colors.transparent, C.indigo.withOpacity(.45)],
          stops: const [.78, 1], transform: GradientRotation(t * 2 * math.pi),
        ).createShader(Rect.fromCircle(center: c, radius: r)));
    // outgoing pulse ring
    final k = (t * 2) % 1;
    canvas.drawCircle(c, r * k,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 2
          ..color = C.indigoSoft.withOpacity((1 - k) * .5));
  }

  @override
  bool shouldRepaint(_RadarPainter o) => o.t != t || o.active != active;
}
