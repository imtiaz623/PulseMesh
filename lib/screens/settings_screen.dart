import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mesh_service.dart';
import '../theme.dart';
import '../widgets.dart';

// ============================================================ Tab 3: Settings & Profile
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _name =
      TextEditingController(text: context.read<MeshService>().myName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(MeshService mesh) async {
    FocusScope.of(context).unfocus();
    await mesh.setName(_name.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    }
  }

  Future<void> _clear(MeshService mesh) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Clear local data?'),
        content: const Text('All chats, media and saved peers on this phone will be deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171)))),
        ],
      ),
    );
    if (ok == true) await mesh.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text('Profile',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.5))),
      _Card(children: [
        Center(child: PeerAvatar(name: mesh.myName, color: mesh.myColor, size: 88)),
        const SizedBox(height: 16),
        TextField(
          controller: _name, maxLength: 24,
          onSubmitted: (_) => _save(mesh),
          decoration: InputDecoration(
            labelText: 'Display name', filled: true, fillColor: C.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            suffixIcon: IconButton(icon: const Icon(Icons.check_circle, color: C.indigo), onPressed: () => _save(mesh))),
        ),
        const SizedBox(height: 6),
        const Text('Avatar color', style: TextStyle(color: C.muted, fontSize: 13)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (var i = 0; i < C.avatars.length; i++)
            GestureDetector(
              onTap: () => mesh.setColor(i),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: C.avatars[i], shape: BoxShape.circle,
                  border: Border.all(color: mesh.myColor % 8 == i ? Colors.white : Colors.transparent, width: 2.5)),
                child: mesh.myColor % 8 == i ? const Icon(Icons.check, size: 20) : null),
            ),
        ]),
      ]),
      const SizedBox(height: 16),
      _Card(children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mesh active'),
          subtitle: const Text('Advertise and discover nearby PulseMesh users',
              style: TextStyle(color: C.muted, fontSize: 12.5)),
          value: mesh.wantRunning,
          onChanged: (v) => v ? mesh.start() : mesh.stop(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-Bluetooth'),
          subtitle: const Text('Ask to turn Bluetooth on whenever it is off',
              style: TextStyle(color: C.muted, fontSize: 12.5)),
          value: mesh.autoBluetooth,
          onChanged: mesh.setAutoBluetooth,
        ),
      ]),
      const SizedBox(height: 16),
      _Card(children: [
        const Text('Storage', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Everything lives in a local SQLite database on this phone. Nothing is uploaded.',
            style: TextStyle(color: C.muted, fontSize: 13)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _clear(mesh),
          icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
          label: const Text('Clear chats, media and peers', style: TextStyle(color: Color(0xFFF87171))),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: C.line)),
        ),
      ]),
      const SizedBox(height: 16),
      Center(
        child: Text('PulseMesh 1.0 · device ${mesh.myId}',
            style: const TextStyle(color: C.muted, fontSize: 12))),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}
