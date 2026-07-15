// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/game_prescription.dart';
import '../models/patient.dart';
import '../state/app_state_scope.dart';
import '../widgets/patient_avatar.dart';
import '../widgets/prescription_summary_card.dart';
import '../services/cube_registry.dart';
import 'analytics_screen.dart';
import 'exercise_control_screen.dart';
import 'patient_form_screen.dart';
import 'prescription_edit_screen.dart';
import 'fsr_calibration_screen.dart';
import 'flex_calibration_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;

  const PatientDetailScreen({super.key, required this.patientId});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppStateScope.of(context).setActivePatient(widget.patientId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final Patient? patient = appState.patients
        .cast<Patient?>()
        .firstWhere((p) => p!.id == widget.patientId, orElse: () => null);

    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient')),
        body: const Center(child: Text('Patient not found.')),
      );
    }

    final avatarColor = colorForPatientId(patient.id);
    final gameTypes = [GameType.cubesBoxes, GameType.pinch, GameType.bend];

    return Scaffold(
      appBar: AppBar(
        title: Text(patient.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Patient',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientFormScreen(existingPatient: patient),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [avatarColor, avatarColor.withOpacity(0.65)],
              ),
              boxShadow: [
                BoxShadow(
                  color: avatarColor.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                      ),
                      child: PatientAvatar(id: patient.id, name: patient.name, radius: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (patient.age != null)
                            Text(
                              'Age ${patient.age}',
                              style: TextStyle(color: Colors.white.withOpacity(0.85)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (patient.notes != null && patient.notes!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            patient.notes!,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Calibration Actions Card
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 10),
                      Text(
                        'Sensor Calibration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const FsrCalibrationScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.scale_rounded, size: 18),
                          label: const Text('Force (FSR)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const FlexCalibrationScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.back_hand_rounded, size: 18),
                          label: const Text('Flex Sensors'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnalyticsScreen(patientId: patient.id, patientName: patient.name),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              side: const BorderSide(color: Color(0xFF8B5CF6)),
              padding: const EdgeInsets.all(14),
            ),
            icon: const Icon(Icons.insights_rounded),
            label: const Text('View progress & analytics'),
          ),
          const SizedBox(height: 24),
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 10),
                      Text(
                        'Active Cubes Configuration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select which cubes are active for this patient. Exercises will only pick target cubes from this selected list.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (CubeRegistry.registry.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'No cubes are enrolled in settings. Go to the dashboard settings to register cubes.',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                      ),
                    )
                  else
                    ...CubeRegistry.registry.values.map((cube) {
                      final isSelected = patient.activeCubeUids.isEmpty ||
                          patient.activeCubeUids.contains(cube.uid);
                      
                      Color displayColor = Colors.white70;
                      if (cube.colorHex.toLowerCase() == 'red') displayColor = Colors.redAccent;
                      else if (cube.colorHex.toLowerCase() == 'green') displayColor = Colors.greenAccent;
                      else if (cube.colorHex.toLowerCase() == 'blue') displayColor = Colors.blueAccent;
                      else if (cube.colorHex.toLowerCase() == 'yellow') displayColor = Colors.yellowAccent;

                      IconData shapeIcon = Icons.crop_square_rounded;
                      if (cube.shape.toLowerCase() == 'circle') {
                        shapeIcon = Icons.circle;
                      } else if (cube.shape.toLowerCase() == 'triangle') {
                        shapeIcon = Icons.change_history_rounded;
                      } else if (cube.shape.toLowerCase() == 'star') {
                        shapeIcon = Icons.star_rounded;
                      } else if (cube.shape.toLowerCase() == 'hexagon') {
                        shapeIcon = Icons.hexagon_rounded;
                      }

                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: const Color(0xFF8B5CF6),
                        checkColor: Colors.white,
                        title: Text(cube.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          'Shape: ${cube.shape} · Color: ${cube.colorHex} · Weight: ${cube.weightGrams}g',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        secondary: Icon(shapeIcon, color: displayColor),
                        onChanged: (checked) {
                          if (checked == null) return;
                          final currentActive = patient.activeCubeUids.isEmpty
                              ? CubeRegistry.registry.keys.toList()
                              : List<String>.from(patient.activeCubeUids);

                          if (checked) {
                            if (!currentActive.contains(cube.uid)) {
                              currentActive.add(cube.uid);
                            }
                          } else {
                            if (currentActive.length <= 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('At least one active cube must be selected for the patient.'),
                                  backgroundColor: Colors.orangeAccent,
                                ),
                              );
                              return;
                            }
                            currentActive.remove(cube.uid);
                          }
                          appState.updatePatientActiveCubes(patient.id, currentActive);
                        },
                      );
                    }).toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Prescriptions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a card to edit, or press play to start the exercise on the glove.',
            style: TextStyle(color: Colors.grey, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          for (final gameType in gameTypes)
            PrescriptionSummaryCard(
              prescription: patient.prescriptions[gameType]!,
              onEdit: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrescriptionEditScreen(
                      patientId: patient.id,
                      prescription: patient.prescriptions[gameType]!,
                    ),
                  ),
                );
              },
              onStart: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExerciseControlScreen(
                      patientId: patient.id,
                      patientName: patient.name,
                      prescription: patient.prescriptions[gameType]!,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
