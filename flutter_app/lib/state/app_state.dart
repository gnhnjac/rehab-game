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
    try {
      _patients = await repository.getAllPatients();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print("Error loading patients: $e");
      }
    }
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
      final patient = _patients.firstWhere((p) => p.id == patientId);
      final cal = patient.calibration;
      
      // Parse list of integers safely from JSON structure
      final flexMin = (cal['flex_min'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [0, 0, 0, 0, 0];
      final flexMax = (cal['flex_max'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [4095, 4095, 4095, 4095, 4095];
      final forceMin = (cal['fo_min'] as num? ?? 4095).toInt();
      final forceMax = (cal['fo_max'] as num? ?? 0).toInt();
      
      final api = GloveApiService();
      final List<Future> futures = [];
      for (int i = 0; i < 5; i++) {
        if (i < flexMin.length && i < flexMax.length) {
          futures.add(api.calibrateFlex(
            fingerIndex: i,
            flexMin: flexMin[i],
            flexMax: flexMax[i],
          ));
        }
      }
      futures.add(api.calibrateForce(forceMin: forceMin, forceMax: forceMax));
      
      // Wait for all calibrations to finish concurrently
      await Future.wait(futures);
      
      await api.sendCommand("ready");
    } catch (e) {
      if (kDebugMode) {
        print("Failed to sync patient calibration or ready state to glove: $e");
      }
    }
  }
}
