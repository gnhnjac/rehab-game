// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';

import '../services/glove_api_service.dart';
import '../services/telemetry_provider.dart';
import '../state/app_state_scope.dart';
import '../repositories/patient_repository_provider.dart';

class FsrCalibrationScreen extends StatefulWidget {
  const FsrCalibrationScreen({super.key});

  @override
  State<FsrCalibrationScreen> createState() => _FsrCalibrationScreenState();
}

class _FsrCalibrationScreenState extends State<FsrCalibrationScreen> {
  static const Color _accent = Color(0xFF8B5CF6); // Purple

  final GloveApiService _api = GloveApiService();
  StreamSubscription? _telemetrySub;
  int _liveRaw = 4095;
  bool _online = false;
  bool _saving = false;

  int? _capturedMin; // Rest baseline
  int? _capturedMax; // Squeeze baseline

  @override
  void initState() {
    super.initState();
    TelemetryProvider.getService().disconnect(); // Stop background polling
    _online = true; // Assume online for initial capture
  }

  @override
  void dispose() {
    TelemetryProvider.getService().connect(); // Restart background polling
    super.dispose();
  }

  Future<void> _captureRest() async {
    setState(() => _saving = true);
    try {
      final raw = await _api.fetchRawSensors();
      setState(() {
        _capturedMin = raw.forceRaw;
        _liveRaw = raw.forceRaw;
        _online = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Captured unpressed rest baseline (Raw: ${raw.forceRaw})'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _online = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing rest value: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _captureSqueeze() async {
    setState(() => _saving = true);
    try {
      final raw = await _api.fetchRawSensors();
      setState(() {
        _capturedMax = raw.forceRaw;
        _liveRaw = raw.forceRaw;
        _online = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Captured maximum squeeze baseline (Raw: ${raw.forceRaw})'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _online = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing squeeze value: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _saving = false);
    }
  }


  Future<void> _saveCalibration() async {
    if (_capturedMin == null || _capturedMax == null) return;
    if (_capturedMax! >= _capturedMin!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Maximum squeeze raw value must be lower than the rest value (FSR raw values decrease under pressure).')),
      );
      return;
    }

    final appState = AppStateScope.of(context);
    final activePatient = appState.activePatient;
    if (activePatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an active patient on the list first')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // 1. Upload to Glove hardware
      await _api.calibrateForce(
        forceMin: _capturedMin!,
        forceMax: _capturedMax!,
      );

      // 2. Save to Firestore via PatientRepository
      final repo = PatientRepositoryProvider.getRepository();
      final Map<String, dynamic> calData = {
        'flex_min': activePatient.calibration['flex_min'] ?? [0, 0, 0, 0, 0],
        'flex_max': activePatient.calibration['flex_max'] ?? [4095, 4095, 4095, 4095, 4095],
        'fsr_coef_a': activePatient.calibration['fsr_coef_a'] ?? 0.0,
        'fsr_coef_b': activePatient.calibration['fsr_coef_b'] ?? 0.0,
        'fsr_coef_c': activePatient.calibration['fsr_coef_c'] ?? 0.0,
        'fo_min': _capturedMin!,
        'fo_max': _capturedMax!,
      };

      await repo.updateCalibration(activePatient.id, calData);
      
      // Sync local app state
      await appState.loadPatients();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Force calibration saved successfully for ${activePatient.name}!'),
          backgroundColor: _accent,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving calibration: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final activePatient = appState.activePatient;

    // Calculate dynamic percentage
    double squeezePercentage = 0.0;
    if (_capturedMin != null && _capturedMax != null && _capturedMin != _capturedMax) {
      squeezePercentage = ((_liveRaw - _capturedMin!) / (_capturedMax! - _capturedMin!)).clamp(0.0, 1.0);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Force Sensor Calibration'),
        backgroundColor: const Color(0xFF141722),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection & Active Patient Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141722),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF232A3D)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _online ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _online ? Icons.wifi_tethering_rounded : Icons.portable_wifi_off_rounded,
                      color: _online ? Colors.green : Colors.red,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activePatient != null ? 'Patient: ${activePatient.name}' : 'No active patient selected',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _online ? 'Glove status: Ready to calibrate' : 'Glove status: Offline (Check Wi-Fi)',
                          style: TextStyle(color: _online ? Colors.green : Colors.red, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Live Raw Feed
            const Text('Live Pinch Force', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141722),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF232A3D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("FSR Sensor", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('ADC: $_liveRaw | range: ${_capturedMin ?? 4095} - ${_capturedMax ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: squeezePercentage,
                      minHeight: 12,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(_accent.withOpacity(0.85)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Wizard Action Steps
            const Text('Calibration Steps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(Icons.touch_app_outlined, color: Colors.cyan, size: 28),
                          const SizedBox(height: 8),
                          const Text('Step 1: Rest', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          const Text('Do NOT touch the sensor', style: TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onPressed: _online ? _captureRest : null,
                            child: const Text('Capture Rest', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(Icons.front_hand_rounded, color: Colors.amber, size: 28),
                          const SizedBox(height: 8),
                          const Text('Step 2: Squeeze', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          const Text('Squeeze at max force', style: TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onPressed: _online ? _captureSqueeze : null,
                            child: const Text('Capture Squeeze', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Save Panel
            if (_capturedMin != null && _capturedMax != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 10),
                        Text('Calibration capture completed!', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _saving ? null : _saveCalibration,
                        child: _saving
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Force Limits to Patient', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
