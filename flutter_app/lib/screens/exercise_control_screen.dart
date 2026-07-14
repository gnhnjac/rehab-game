// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:math';
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
  bool _gameRunning = false;

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
      if (!mounted) return;
      
      // Live session start transition
      if (t.sessionActive && !_gameRunning) {
        _gameRunning = true;
        _sessionStarted = true;
      }
      
      // Live session end transition
      if (!t.sessionActive && _gameRunning) {
        _gameRunning = false;
        _sessionStarted = false;
        _showSessionFinishedDialog(t.successCount, t.failureCount, t.sessionCompletedSuccess);
      }
      
      setState(() => _latest = t);
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
            .map((c) => GloveCube(
                  uid: c.uid,
                  color: c.colorHex,
                  shape: c.shape,
                  weightGrams: c.weightGrams,
                ))
            .toList();
      }
      await _api.sendActivePrescription(
        prescription: widget.prescription,
        patientId: widget.patientId,
        cubes: cubes,
      );
      if (!mounted) return;
      setState(() {
        _sessionStarted = true;
      });
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

  Future<void> _stopExercise() async {
    setState(() => _starting = true);
    try {
      await _api.stopActivePrescription();
      if (!mounted) return;
      setState(() {
        _sessionStarted = false;
        _gameRunning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Exercise stopped'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not stop: $e'), backgroundColor: Colors.redAccent),
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
                widget.prescription.type == GameType.bend
                    ? 'Flex'
                    : (widget.prescription.type == GameType.cubesBoxes ? 'Status' : 'Force'),
                widget.prescription.type == GameType.bend
                    ? (t != null && t!.flex.percent.isNotEmpty
                        ? '${(t!.flex.percent.reduce((a, b) => a + b) / t!.flex.percent.length).round()}%'
                        : '—')
                    : (widget.prescription.type == GameType.cubesBoxes
                        ? 'Active'
                        : (t != null && t!.force.percent.isNotEmpty ? '${t!.force.percent.first}g' : '—')),
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
    final bool active = _gameRunning || _sessionStarted;
    return ElevatedButton.icon(
      onPressed: _starting
          ? null
          : active
              ? _stopExercise
              : _startExercise,
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? Colors.redAccent : color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(18),
      ),
      icon: _starting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: Text(_starting
          ? 'Starting…'
          : active
              ? 'Stop exercise'
              : 'Start exercise'),
    );
  }

  void _showSessionFinishedDialog(int successes, int failures, bool completedSuccess) {
    final color = completedSuccess ? Colors.greenAccent : Colors.redAccent;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF141722),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: color.withOpacity(0.5), width: 2),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (completedSuccess)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: ConfettiDialogContent(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        completedSuccess ? Icons.emoji_events_rounded : Icons.timer_off_rounded,
                        color: color,
                        size: 50,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      completedSuccess ? 'התרגיל הושלם בהצלחה!' : 'פג הזמן!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      completedSuccess
                          ? 'כל הכבוד! סיימת את כל ${widget.prescription.cycles} המחזורים.'
                          : 'לא נורא! נסה שוב להשלים את התרגיל בזמן.',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F111A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildDialogStat('הצלחות', '$successes', Colors.greenAccent),
                          _buildDialogStat('שגיאות', '$failures', Colors.redAccent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'סגור',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDialogStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}

class Particle {
  double x, y, vx, vy, size;
  Color color;
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
  });
}

class ConfettiPainter extends CustomPainter {
  final List<Particle> particles;
  ConfettiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      paint.color = p.color;
      canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ConfettiDialogContent extends StatefulWidget {
  const ConfettiDialogContent({super.key});

  @override
  State<ConfettiDialogContent> createState() => _ConfettiDialogContentState();
}

class _ConfettiDialogContentState extends State<ConfettiDialogContent> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..addListener(_updateParticles)
      ..repeat();
    
    // Spawn particles in circular fan shape from top-middle
    for (int i = 0; i < 60; i++) {
      double angle = pi + _random.nextDouble() * pi; // Semi-circle direction
      double speed = _random.nextDouble() * 6 + 4;
      _particles.add(Particle(
        x: 150.0,
        y: -10.0,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        size: _random.nextDouble() * 4 + 2,
        color: Colors.primaries[_random.nextInt(Colors.primaries.length)],
      ));
    }
  }

  void _updateParticles() {
    for (final p in _particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.2; // Gravity
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ConfettiPainter(_particles),
      child: const SizedBox(width: 300, height: 400),
    );
  }
}
