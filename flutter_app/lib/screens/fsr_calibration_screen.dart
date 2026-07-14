// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';

import '../services/glove_api_service.dart';

/// Task I.4 — Calibrate the glove FSR (force sensor) against a digital scale.
///
/// The therapist places known weights on the sensor, reads the grams off a
/// digital scale, and captures the corresponding raw ADC value at three points.
/// The three (raw, grams) pairs are sent to the glove, which interpolates
/// between them to convert future raw readings into grams. Works fully offline
/// via direct local polling of the glove's REST API.
class FsrCalibrationScreen extends StatefulWidget {
  const FsrCalibrationScreen({super.key});

  @override
  State<FsrCalibrationScreen> createState() => _FsrCalibrationScreenState();
}

class _CapturePoint {
  final String label;
  final String hint;
  final TextEditingController gramsController = TextEditingController();
  int? capturedRaw;

  _CapturePoint(this.label, this.hint);
}

class _FsrCalibrationScreenState extends State<FsrCalibrationScreen> {
  static const Color _accent = Color(0xFF10B981);

  final GloveApiService _api = GloveApiService();
  Timer? _pollTimer;
  int? _liveRaw;
  bool _online = false;
  bool _saving = false;

  final List<_CapturePoint> _points = [
    _CapturePoint('Point 1 — no load', 'Grams on scale (e.g. 0)'),
    _CapturePoint('Point 2 — light weight', 'Grams on scale (e.g. 200)'),
    _CapturePoint('Point 3 — heavy weight', 'Grams on scale (e.g. 500)'),
  ];

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final p in _points) {
      p.gramsController.dispose();
    }
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      try {
        final raw = await _api.fetchRawSensors();
        if (!mounted) return;
        setState(() {
          _liveRaw = raw.forceRaw;
          _online = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _online = false);
      }
    });
  }

  void _capture(_CapturePoint point) {
    if (_liveRaw == null) return;
    setState(() => point.capturedRaw = _liveRaw);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Captured raw ${_liveRaw!} for "${point.label}"'),
        backgroundColor: _accent,
      ),
    );
  }

  String? _validationError() {
    final built = <CalibrationPoint>[];
    for (final p in _points) {
      if (p.capturedRaw == null) return 'Capture the raw value for every point.';
      final grams = double.tryParse(p.gramsController.text.trim());
      if (grams == null || grams < 0) return 'Enter a valid grams value for every point.';
      built.add(CalibrationPoint(raw: p.capturedRaw!, grams: grams));
    }
    final raws = built.map((e) => e.raw).toSet();
    if (raws.length != 3) return 'The three captured raw values must differ.';
    return null;
  }

  Future<void> _save() async {
    final error = _validationError();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final points = _points
          .map((p) => CalibrationPoint(
                raw: p.capturedRaw!,
                grams: double.parse(p.gramsController.text.trim()),
              ))
          .toList();
      await _api.calibrateForce(points);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Force calibration saved to glove'),
          backgroundColor: _accent,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FSR Calibration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBanner(),
          const SizedBox(height: 20),
          _buildLiveGauge(),
          const SizedBox(height: 20),
          const Text(
            'Capture points',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Place a known weight on the sensor, read the grams from your digital scale, '
            'type it in, then capture the raw value. Repeat for all three points.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final point in _points) _buildPointCard(point),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Saving…' : 'Save calibration to glove'),
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
          colors: [_accent, Color(0xFF059669)],
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
            child: const Icon(Icons.scale_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Map the force sensor to grams using a digital scale',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveGauge() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232A3D)),
      ),
      child: Row(
        children: [
          Icon(
            _online ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            color: _online ? _accent : Colors.redAccent,
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _online ? 'Live raw FSR' : 'Glove offline',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                _liveRaw?.toString() ?? '—',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPointCard(_CapturePoint point) {
    final captured = point.capturedRaw != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: captured ? _accent.withOpacity(0.5) : const Color(0xFF232A3D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(point.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: point.gramsController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: point.hint,
                    labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF232A3D)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _accent),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0D0E15),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _liveRaw == null ? null : () => _capture(point),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D0E15),
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                child: const Text('Capture'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                captured ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: captured ? _accent : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                captured ? 'Captured raw: ${point.capturedRaw}' : 'Not captured yet',
                style: TextStyle(color: captured ? _accent : Colors.grey, fontSize: 12.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
