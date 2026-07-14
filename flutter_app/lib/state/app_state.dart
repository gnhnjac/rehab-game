import 'package:flutter/foundation.dart';

import '../models/game_prescription.dart';
import '../models/patient.dart';
import '../repositories/patient_repository.dart';
import '../services/glove_api_service.dart';

class AppState extends ChangeNotifier {
  final PatientRepository repository;

  List<Patient> _patients = [];
  String? _activePatientId;

  AppState({required this.repository});

  List<Patient> get patients => List.unmodifiable(_patients);

  Patient? get activePatient {
    final id = _activePatientId;
    if (id == null) return null;
    for (final patient in _patients) {
      if (patient.id == id) return patient;
    }
    return null;
  }

  Future<void> loadPatients() async {
    _patients = await repository.getAllPatients();
    notifyListeners();
  }

  Future<Patient> addPatient({required String name, int? age, String? notes}) async {
    final patient = await repository.addPatient(name: name, age: age, notes: notes);
    await loadPatients();
    return patient;
  }

  Future<void> updatePatient(Patient patient) async {
    await repository.updatePatient(patient);
    await loadPatients();
  }

  Future<void> updatePrescription(String patientId, GamePrescription prescription) async {
    await repository.updatePrescription(patientId, prescription);
    await loadPatients();
  }

  Future<void> setActivePatient(String patientId) async {
    _activePatientId = patientId;
    notifyListeners();
    try {
      await GloveApiService().sendCommand("ready");
    } catch (e) {
      if (kDebugMode) {
        print("Failed to send active patient ready command to glove: $e");
      }
    }
  }
}
