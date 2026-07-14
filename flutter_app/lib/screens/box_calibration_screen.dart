// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';

import '../models/glove_telemetry.dart';
import '../services/box_registry.dart';
import '../services/glove_api_service.dart';
import '../services/telemetry_provider.dart';
import '../services/telemetry_service.dart';

/// Task I.5 — Box Calibration / identity registry.
///
/// Lists the smart boxes currently registered with the glove (from telemetry),
/// lets the therapist flash a box's identification LED to physically locate it,
/// and map each box's MAC address to a friendly name + shape. Mappings persist
/// locally via [BoxRegistry].
class BoxCalibrationScreen extends StatefulWidget {
  const BoxCalibrationScreen({super.key});

  @override
  State<BoxCalibrationScreen> createState() => _BoxCalibrationScreenState();
}

const List<String> _shapes = ['circle', 'square', 'triangle', 'star', 'hexagon'];

const Map<String, IconData> _shapeIcons = {
  'circle': Icons.circle_outlined,
  'square': Icons.crop_square,
  'triangle': Icons.change_history,
  'star': Icons.star_border,
  'hexagon': Icons.hexagon_outlined,
};

class _BoxCalibrationScreenState extends State<BoxCalibrationScreen> {
  static const Color _accent = Color(0xFF3B82F6);

  final GloveApiService _api = GloveApiService();
  TelemetryService? _service;
  StreamSubscription<GloveTelemetry>? _sub;
  List<String> _macs = [];

  @override
  void initState() {
    super.initState();
    BoxRegistry.load().then((_) => setState(() {}));
    _connect();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    final service = TelemetryProvider.getService();
    _service = service;
    _sub = service.telemetryStream.listen((t) {
      final macs = t.boxes.map((b) => b['mac'] ?? '').where((m) => m.isNotEmpty).toList();
      if (mounted && !_listEquals(macs, _macs)) {
        setState(() => _macs = macs);
      }
    });
    if (!service.isConnected) {
      try {
        await service.connect();
      } catch (_) {}
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _flashBox(int index, String mac) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Flashing box ${index + 1}…'), backgroundColor: _accent),
    );
    try {
      // Firmware command hook: identifyBox with the 0-based box index.
      await _api.sendCommand('identifyBox', time: index);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Flash not acknowledged by glove ($e). '
              'The firmware LED-flash command may still be in development.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }

  Future<void> _editBox(String mac) async {
    final existing = BoxRegistry.getBox(mac);
    final nameController = TextEditingController(text: existing?.name ?? '');
    String shape = existing?.shape ?? _shapes.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF141722),
          title: Text('Identify box', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('MAC: $mac', style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'monospace')),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Box name',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: shape,
                dropdownColor: const Color(0xFF141722),
                decoration: const InputDecoration(
                  labelText: 'Shape',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
                items: _shapes
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Row(
                            children: [
                              Icon(_shapeIcons[s], size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(s, style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (val) => setDialogState(() => shape = val ?? shape),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                await BoxRegistry.enrollBox(mac, nameController.text.trim(), shape);
                if (context.mounted) Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final online = _service?.isConnected ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Box Calibration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBanner(),
          const SizedBox(height: 20),
          if (!online)
            _buildInfo(Icons.link_off, 'Glove offline',
                'Connect to the glove to see live boxes. Previously mapped boxes are still shown below.'),
          if (_macs.isEmpty && online)
            _buildInfo(Icons.inbox_outlined, 'No boxes detected',
                'Power on the smart boxes so they register with the glove over ESP-NOW.'),
          ..._buildBoxCards(),
        ],
      ),
    );
  }

  List<Widget> _buildBoxCards() {
    // Union of live boxes and previously mapped boxes.
    final allMacs = <String>{..._macs, ...BoxRegistry.registry.keys}.toList();
    final cards = <Widget>[];
    for (var i = 0; i < allMacs.length; i++) {
      final mac = allMacs[i];
      final mapped = BoxRegistry.getBox(mac);
      final isLive = _macs.contains(mac);
      cards.add(_buildBoxCard(i, mac, mapped, isLive));
    }
    return cards;
  }

  Widget _buildBoxCard(int index, String mac, EnrolledBox? mapped, bool isLive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mapped != null ? _accent.withOpacity(0.5) : const Color(0xFF232A3D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  mapped != null ? _shapeIcons[mapped.shape] ?? Icons.widgets : Icons.help_outline,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mapped?.name ?? 'Unnamed box ${index + 1}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(mac, style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace')),
                  ],
                ),
              ),
              if (isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Live', style: TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLive ? () => _flashBox(index, mac) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9E0B),
                    side: BorderSide(color: isLive ? const Color(0xFFFF9E0B) : Colors.grey),
                  ),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Flash LED'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _editBox(mac),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
                  icon: const Icon(Icons.edit, size: 18),
                  label: Text(mapped != null ? 'Edit' : 'Identify'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent, Color(0xFF1D4ED8)],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Flash a box to locate it, then name it and pick its shape',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(IconData icon, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232A3D)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: Colors.grey[400], fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
