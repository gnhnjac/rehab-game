// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';

import '../services/glove_api_service.dart';
import '../services/telemetry_provider.dart';
import '../state/app_state_scope.dart';
import '../repositories/patient_repository_provider.dart';

class FlexCalibrationScreen extends StatefulWidget {
  const FlexCalibrationScreen({super.key});

  @override
  State<FlexCalibrationScreen> createState() => _FlexCalibrationScreenState();
}

class _FlexCalibrationScreenState extends State<FlexCalibrationScreen> {
  static const Color _accent = Color(0xFF8B5CF6); // Cyber Purple

  final GloveApiService _api = GloveApiService();
  StreamSubscription? _telemetrySub;
  Timer? _pollTimer;
  List<int> _liveRaw = [0, 0, 0, 0, 0];
  bool _online = false;
  bool _saving = false;

  // Stored calibration points
  List<int>? _capturedMin;
  List<int>? _capturedMax;

  final List<String> _fingerNames = [
    "Thumb",
    "Index",
    "Middle",
    "Ring",
    "Pinky"
  ];

  @override
  void initState() {
    super.initState();
    TelemetryProvider.getService().disconnect(); // Stop background polling
    _online = true;

    // Load existing calibration from active patient if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activePatient = AppStateScope.of(context).activePatient;
      if (activePatient != null) {
        final cal = activePatient.calibration;
        if (cal.containsKey('flex_min') && cal.containsKey('flex_max')) {
          final fMinList = cal['flex_min'] as List?;
          final fMaxList = cal['flex_max'] as List?;
          if (fMinList != null && fMaxList != null && fMinList.length == 5 && fMaxList.length == 5) {
            setState(() {
              _capturedMin = List<int>.from(fMinList.map((e) => (e as num).toInt()));
              _capturedMax = List<int>.from(fMaxList.map((e) => (e as num).toInt()));
            });
          }
        }
      }
    });

    _startSlowPoll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    TelemetryProvider.getService().connect(); // Restart background polling
    super.dispose();
  }

  void _startSlowPoll() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      try {
        final raw = await _api.fetchRawSensors();
        if (mounted) {
          setState(() {
            _liveRaw = List<int>.from(raw.flexRaw);
            _online = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _online = false);
      }
    });
  }

  Future<void> _captureOpen() async {
    setState(() => _saving = true);
    try {
      final raw = await _api.fetchRawSensors();
      setState(() {
        _capturedMin = List<int>.from(raw.flexRaw);
        _liveRaw = List<int>.from(raw.flexRaw);
        _online = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Captured open hand baseline (Raw: $_capturedMin)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _online = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing open hand values: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _captureClosed() async {
    setState(() => _saving = true);
    try {
      final raw = await _api.fetchRawSensors();
      setState(() {
        _capturedMax = List<int>.from(raw.flexRaw);
        _liveRaw = List<int>.from(raw.flexRaw);
        _online = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Captured closed hand baseline (Raw: $_capturedMax)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _online = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing closed hand values: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _saveCalibration() async {
    if (_capturedMin == null || _capturedMax == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Please capture both Open and Closed hand baselines before saving.')),
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
      // 1. Save to Firestore via PatientRepository
      final repo = PatientRepositoryProvider.getRepository();
      final Map<String, dynamic> calData = {
        'flex_min': _capturedMin,
        'flex_max': _capturedMax,
        'fo_min': activePatient.calibration['fo_min'] ?? 4095,
        'fo_max': activePatient.calibration['fo_max'] ?? 0,
      };

      debugPrint("Saving Flex Calibration: ID=${activePatient.id}, Min=$_capturedMin, Max=$_capturedMax");
      await repo.updateCalibration(activePatient.id, calData);
      
      // Update local app state patient data instantly
      appState.updatePatientCalibrationLocally(activePatient.id, calData);
      
      // 2. Sync new calibration to the Glove (non-blocking if offline)
      bool gloveSyncSuccess = true;
      String? gloveError;
      try {
        await appState.setActivePatient(activePatient.id);
      } catch (e) {
        gloveSyncSuccess = false;
        gloveError = e.toString();
      }

      if (!mounted) return;
      if (gloveSyncSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calibration saved successfully to Firestore & Glove for ${activePatient.name} (ID: ${activePatient.id})!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to database for ${activePatient.name} (ID: ${activePatient.id}), but Glove sync failed: $gloveError. It will sync when starting game.'),
            backgroundColor: Colors.orangeAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flex Sensor Calibration'),
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
            const Text('Live Sensor Values', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF141722),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF232A3D)),
              ),
              child: Column(
                children: List.generate(5, (index) {
                  final rawVal = index < _liveRaw.length ? _liveRaw[index] : 0;
                  final minVal = _capturedMin != null ? _capturedMin![index] : 0;
                  final maxVal = _capturedMax != null ? _capturedMax![index] : 4095;
                  
                  // Calculate dynamic percentage
                  double percentage = 0.0;
                  if (maxVal != minVal) {
                    percentage = ((rawVal - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fingerNames[index], style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('ADC: $rawVal | range: $minVal - $maxVal', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percentage,
                            minHeight: 10,
                            backgroundColor: Colors.white.withOpacity(0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(_accent.withOpacity(0.85)),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
                          const Icon(Icons.back_hand_rounded, color: Colors.cyan, size: 28),
                          const SizedBox(height: 8),
                          const Text('Step 1: Open Hand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          const Text('Flatten hand completely', style: TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onPressed: _online ? _captureOpen : null,
                            child: const Text('Capture Open', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                          const Text('Step 2: Close Fist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          const Text('Close fingers tightly', style: TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onPressed: _online ? _captureClosed : null,
                            child: const Text('Capture Fist', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.save, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('SAVE CALIBRATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                ],
                              ),
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
