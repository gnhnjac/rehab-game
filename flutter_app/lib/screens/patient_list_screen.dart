// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../state/app_state_scope.dart';

import '../widgets/patient_avatar.dart';
import 'box_calibration_screen.dart';
import 'cube_calibration_screen.dart';
import 'flex_calibration_screen.dart';
import 'fsr_calibration_screen.dart';
import 'patient_detail_screen.dart';
import 'patient_form_screen.dart';

class PatientListScreen extends StatelessWidget {
  const PatientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final patients = appState.patients;
    final activePatient = appState.activePatient;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
      ),

      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.groups_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${patients.length} ${patients.length == 1 ? 'patient' : 'patients'} enrolled',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activePatient != null
                            ? 'Active: ${activePatient.name} (ID: ${activePatient.id})'
                            : 'No active patient selected',
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildCalibrationCard(
                        context: context,
                        icon: Icons.scale_rounded,
                        title: 'Force Sensor',
                        subtitle: 'Calibrate FSR',
                        color: const Color(0xFF8B5CF6),
                        enabled: activePatient != null,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const FsrCalibrationScreen())),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildCalibrationCard(
                        context: context,
                        icon: Icons.back_hand_rounded,
                        title: 'Flex Sensors',
                        subtitle: 'Patient Range',
                        color: const Color(0xFF3B82F6),
                        enabled: activePatient != null,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const FlexCalibrationScreen())),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildCalibrationCard(
                        context: context,
                        icon: Icons.grid_view_rounded,
                        title: 'Smart Boxes',
                        subtitle: 'Flash LEDs',
                        color: const Color(0xFF10B981),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const BoxCalibrationScreen())),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildCalibrationCard(
                        context: context,
                        icon: Icons.nfc_rounded,
                        title: 'RFID Cubes',
                        subtitle: 'Register Tags',
                        color: Colors.orangeAccent,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const CubeCalibrationScreen())),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: patients.isEmpty

                ? const Center(
                    child: Text('No patients yet — tap + to add one.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: patients.length,
                    itemBuilder: (context, index) {
                      final patient = patients[index];
                      final isActive = appState.activePatient?.id == patient.id;
                      final avatarColor = colorForPatientId(patient.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive
                                ? avatarColor.withOpacity(0.6)
                                : const Color(0xFF232A3D),
                          ),
                        ),
                        child: Material(
                          color: isActive
                              ? avatarColor.withOpacity(0.12)
                              : const Color(0xFF141722),
                          borderRadius: BorderRadius.circular(14),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: PatientAvatar(id: patient.id, name: patient.name),
                            title: Text(
                              patient.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text([
                              if (patient.age != null) 'Age ${patient.age}',
                              if (patient.notes != null && patient.notes!.isNotEmpty)
                                patient.notes!,
                            ].join(' · ')),
                            trailing: isActive
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: avatarColor,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Active',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientDetailScreen(patientId: patient.id),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PatientFormScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCalibrationCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141722),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF232A3D)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled
                ? onTap
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select an active patient from the list below before calibrating.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

