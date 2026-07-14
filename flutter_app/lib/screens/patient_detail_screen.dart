// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/game_prescription.dart';
import '../models/patient.dart';
import '../state/app_state_scope.dart';
import '../widgets/patient_avatar.dart';
import '../widgets/prescription_summary_card.dart';
import 'analytics_screen.dart';
import 'exercise_control_screen.dart';
import 'patient_form_screen.dart';
import 'prescription_edit_screen.dart';

class PatientDetailScreen extends StatelessWidget {
  final String patientId;

  const PatientDetailScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final Patient? patient = appState.patients
        .cast<Patient?>()
        .firstWhere((p) => p!.id == patientId, orElse: () => null);

    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient')),
        body: const Center(child: Text('Patient not found.')),
      );
    }

    final isActive = appState.activePatient?.id == patient.id;
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isActive
                        ? null
                        : () {
                            appState.setActivePatient(patient.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${patient.name} set as active patient')),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: avatarColor,
                      disabledBackgroundColor: Colors.white.withOpacity(0.85),
                      disabledForegroundColor: avatarColor,
                    ),
                    icon: Icon(isActive ? Icons.check_circle_rounded : Icons.person_pin_rounded),
                    label: Text(isActive ? 'Active Patient' : 'Set Active Patient'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
