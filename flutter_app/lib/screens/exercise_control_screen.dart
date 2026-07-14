// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';

import '../models/game_prescription.dart';
import '../models/glove_telemetry.dart';
import '../services/cube_registry.dart';
import '../services/glove_api_service.dart';
import '../services/telemetry_provider.dart';
import '../services/telemetry_service.dart';
import '../widgets/prescription_summary_card.dart';

/// Task I.2 — Active Exercise Control.
///
/// Pushes the chosen prescription to the glove (`/api/active-prescription`),
/// then reflects the live session: instructions, countdown timer, cycle
/// progress and a start trigger. The glove runs the actual game logic; this
/// screen mirrors its telemetry.
class ExerciseControlScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final GamePrescription prescription;

  const ExerciseControlScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.prescription,
  });

  @override
  State<ExerciseControlScreen> createState() => _ExerciseControlScreenState();
}

class _ExerciseControlScreenState extends State<ExerciseControlScreen> {
  final GloveApiService _api = GloveApiService();
  TelemetryService? _service;
  StreamSubscription<GloveTelemetry>? _sub;
  GloveTelemetry? _latest;
  bool _sessionStarted = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _connectTelemetry();
  }

  @override
  void dispose() {
    // Cancel only our subscription; leave the shared service alone so other
    // screens using it aren't disrupted.
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _connectTelemetry() async {
    final service = TelemetryProvider.getService();
    _service = service;
    _sub = service.telemetryStream.listen((t) {
      if (mounted) setState(() => _latest = t);
    });
    if (!service.isConnected) {
      try {
        await service.connect();
      } catch (_) {
        // Surface via the offline indicator rather than throwing.
      }
    }
  }

  Future<void> _startExercise() async {
    setState(() => _starting = true);
    try {
      List<GloveCube> cubes = const [];
      if (widget.prescription.type == GameType.cubesBoxes) {
        cubes = CubeRegistry.registry.values
            .map((c) => GloveCube(uid: c.uid, color: c.colorHex, shape: 'cube', weightGrams: 0))
            .toList();
      }
      await _api.sendActivePrescription(
        prescription: widget.prescription,
        patientId: widget.patientId,
        cubes: cubes,
      );
      if (!mounted) return;
      setState(() => _sessionStarted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Exercise started on glove'),
          backgroundColor: gameTypeColor(widget.prescription.type),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String get _instructions {
    switch (widget.prescription.type) {
      case GameType.cubesBoxes:
        return 'Move the weighted cubes between the smart boxes before each cycle timer runs out.';
      case GameType.pinch:
        return 'Pinch the sensor to reach the target force and hold it for the required time, once per cycle.';
      case GameType.bend:
        return 'Bend your fingers to reach the target range of motion and hold, once per cycle.';
    }
  }

  bool get _online => _service?.isConnected ?? false;

  @override
  Widget build(BuildContext context) {
    final color = gameTypeColor(widget.prescription.type);
    return Scaffold(
      appBar: AppBar(title: Text('Exercise · ${gameTypeLabel(widget.prescription.type)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBanner(color),
          const SizedBox(height: 16),
          _buildInstructionsCard(color),
          const SizedBox(height: 16),
          _buildStatusCard(color),
          const SizedBox(height: 20),
          _buildStartButton(color),
        ],
      ),
    );
  }

  Widget _buildBanner(Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withOpacity(0.65)],
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
            child: Icon(gameTypeIcon(widget.prescription.type), color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gameTypeLabel(widget.prescription.type),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Patient: ${widget.patientName}',
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                ),
              ],
            ),
          ),
          _buildOnlinePill(),
        ],
      ),
    );
  }

  Widget _buildOnlinePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_online ? Icons.link : Icons.link_off, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(_online ? 'Online' : 'Offline',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard(Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232A3D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text('Instructions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_instructions, style: TextStyle(color: Colors.grey[400], height: 1.4)),
          const Divider(color: Color(0xFF232A3D), height: 24),
          Text(prescriptionSummary(widget.prescription),
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusCard(Color color) {
    final t = _latest;
    final timeRemaining = t?.timeRemaining ?? 0;
    final calibrating = t?.calibrating ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232A3D)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('Cycles', '${widget.prescription.cycles}', color),
              _buildStat(
                'Time left',
                _sessionStarted ? '${timeRemaining}s' : '—',
                color,
              ),
              _buildStat(
                'Force',
                t != null && t.force.percent.isNotEmpty ? '${t.force.percent.first}%' : '—',
                color,
              ),
            ],
          ),
          if (calibrating) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(color: Color(0xFFFF9E0B), backgroundColor: Color(0xFF232A3D)),
            const SizedBox(height: 8),
            const Text('Glove is calibrating…', style: TextStyle(color: Color(0xFFFF9E0B), fontSize: 12)),
          ] else if (_sessionStarted) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: null,
              color: color,
              backgroundColor: const Color(0xFF232A3D),
            ),
            const SizedBox(height: 8),
            Text('Session running on glove…', style: TextStyle(color: color, fontSize: 12)),
          ] else ...[
            const SizedBox(height: 16),
            Text('Press start to push this prescription to the glove.',
                style: TextStyle(color: Colors.grey[500], fontSize: 12), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      ],
    );
  }

  Widget _buildStartButton(Color color) {
    return ElevatedButton.icon(
      onPressed: _starting ? null : _startExercise,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(18),
      ),
      icon: _starting
          ? const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(_sessionStarted ? Icons.refresh_rounded : Icons.play_arrow_rounded),
      label: Text(_starting
          ? 'Starting…'
          : _sessionStarted
              ? 'Restart exercise'
              : 'Start exercise'),
    );
  }
}
