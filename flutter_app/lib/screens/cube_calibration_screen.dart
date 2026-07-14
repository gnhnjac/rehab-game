// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';

import '../models/glove_telemetry.dart';
import '../services/cube_registry.dart';
import '../services/telemetry_provider.dart';
import '../services/telemetry_service.dart';

class CubeCalibrationScreen extends StatefulWidget {
  const CubeCalibrationScreen({super.key});

  @override
  State<CubeCalibrationScreen> createState() => _CubeCalibrationScreenState();
}

class _CubeCalibrationScreenState extends State<CubeCalibrationScreen> {
  static const Color _accent = Color(0xFF10B981); // Emerald Green

  TelemetryService? _service;
  StreamSubscription<GloveTelemetry>? _sub;
  String? _detectedUid;
  
  final _nameController = TextEditingController();
  String _selectedColor = "Red";

  final List<String> _colors = ["Red", "Green", "Blue", "Yellow", "Purple", "Cyan", "White"];

  @override
  void initState() {
    super.initState();
    CubeRegistry.load().then((_) => setState(() {}));
    _connect();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final service = TelemetryProvider.getService();
    _service = service;
    _sub = service.telemetryStream.listen((t) {
      // Find the first non-empty cube UID in any registered box
      String? foundUid;
      for (final box in t.boxes) {
        final cubeUid = box['cube'] as String?;
        if (cubeUid != null && cubeUid.isNotEmpty) {
          foundUid = cubeUid;
          break;
        }
      }
      
      if (mounted && foundUid != _detectedUid) {
        setState(() {
          _detectedUid = foundUid;
          if (foundUid != null) {
            // Suggest a default name if not enrolled
            final enrolled = CubeRegistry.getCube(foundUid);
            if (enrolled != null) {
              _nameController.text = enrolled.name;
              _selectedColor = enrolled.colorHex;
            } else {
              _nameController.text = "Cube #${foundUid.substring(0, 4)}";
            }
          }
        });
      }
    });

    if (!service.isConnected) {
      try {
        await service.connect();
      } catch (_) {}
    }
  }

  Future<void> _registerCube() async {
    if (_detectedUid == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for the cube')),
      );
      return;
    }

    await CubeRegistry.enrollCube(_detectedUid!, name, _selectedColor);
    if (!mounted) return;
    
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cube "$name" registered successfully!'),
        backgroundColor: _accent,
      ),
    );
  }

  Future<void> _deleteCube(String uid) async {
    await CubeRegistry.deleteCube(uid);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cube removed from registry')),
      );
    }
  }

  Color _getColorFromLabel(String label) {
    switch (label) {
      case "Red": return Colors.red;
      case "Green": return Colors.green;
      case "Blue": return Colors.blue;
      case "Yellow": return Colors.amber;
      case "Purple": return Colors.purple;
      case "Cyan": return Colors.cyan;
      case "White": return Colors.white;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubes = CubeRegistry.registry.values.toList();
    final isGloveConnected = _service?.isConnected ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RFID Cube Registration'),
        backgroundColor: const Color(0xFF141722),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Glove Connection Status Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isGloveConnected ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    isGloveConnected ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isGloveConnected
                          ? 'Connected to Glove. Place a cube in any box to scan UIDs.'
                          : 'Disconnected from Glove. Please check telemetry connection settings.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Scan / Form Card
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
                  const Text(
                    'Step 1: Scan RFID Tag',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (_detectedUid == null)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            CircularProgressIndicator(strokeWidth: 2.5),
                            SizedBox(height: 14),
                            Text(
                              'Awaiting NFC tag scan... Place a cube in a smart box',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Found UID!
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.nfc_rounded, color: _accent),
                          const SizedBox(width: 10),
                          Text(
                            'Scanned UID: ${_detectedUid!}',
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Step 2: Enter Cube Details',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Cube Display Name',
                        hintText: 'e.g. Red Circle Cube',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedColor,
                      decoration: const InputDecoration(
                        labelText: 'Cube Color Indicator',
                        border: OutlineInputBorder(),
                      ),
                      items: _colors.map((c) {
                        return DropdownMenuItem<String>(
                          value: c,
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _getColorFromLabel(c),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade600),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(c),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedColor = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _registerCube,
                        child: const Text('Register & Save Cube', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Enrolled Cubes Registry List
            const Text(
              'Enrolled Cube Registry',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (cubes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No cubes registered yet.', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cubes.length,
                itemBuilder: (context, index) {
                  final cube = cubes[index];
                  final dotColor = _getColorFromLabel(cube.colorHex);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: dotColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.nfc_rounded, color: dotColor, size: 20),
                      ),
                      title: Text(cube.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'UID: ${cube.uid} · Color: ${cube.colorHex}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _deleteCube(cube.uid),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
