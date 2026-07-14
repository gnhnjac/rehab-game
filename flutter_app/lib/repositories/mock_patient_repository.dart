import '../models/game_prescription.dart';
import '../models/patient.dart';
import 'patient_repository.dart';

class MockPatientRepository implements PatientRepository {
  final Map<String, Patient> _patients = {};
  int _nextId = 1;

  MockPatientRepository() {
    _seed();
  }

  void _seed() {
    _createSeeded(name: 'Noa Levi', age: 62, notes: 'Post-stroke, right hand');
    _createSeeded(name: 'David Cohen', age: 58, notes: 'Wrist fracture recovery');
  }

  void _createSeeded({required String name, int? age, String? notes}) {
    final id = 'p${_nextId++}';
    _patients[id] = Patient(
      id: id,
      name: name,
      age: age,
      notes: notes,
      prescriptions: _defaultPrescriptions(),
      calibration: _defaultCalibration(),
    );
  }

  Map<GameType, GamePrescription> _defaultPrescriptions() {
    return {
      GameType.cubesBoxes: const CubesBoxesPrescription(
        cycles: 3,
        timerSeconds: 60,
        targetWeightGrams: 200,
      ),
      GameType.pinch: const PinchPrescription(
        cycles: 10,
        holdDurationSeconds: 5,
        targetForceGrams: 500,
      ),
      GameType.bend: const BendPrescription(
        cycles: 10,
        holdDurationSeconds: 5,
        targetRomPercent: 70,
      ),
    };
  }

  Map<String, dynamic> _defaultCalibration() {
    return {
      'flex_min': [0, 0, 0, 0, 0],
      'flex_max': [4095, 4095, 4095, 4095, 4095],
      'fsr_coef_a': 0.0,
      'fsr_coef_b': 0.0,
      'fsr_coef_c': 0.0,
    };
  }

  @override
  Future<List<Patient>> getAllPatients() async {
    return _patients.values.toList(growable: false);
  }

  @override
  Future<Patient?> getPatientById(String id) async {
    return _patients[id];
  }

  @override
  Future<Patient> addPatient({required String name, int? age, String? notes}) async {
    final id = 'p${_nextId++}';
    final patient = Patient(
      id: id,
      name: name,
      age: age,
      notes: notes,
      prescriptions: _defaultPrescriptions(),
      calibration: _defaultCalibration(),
    );
    _patients[id] = patient;
    return patient;
  }

  @override
  Future<Patient> updatePatient(Patient patient) async {
    if (!_patients.containsKey(patient.id)) {
      throw ArgumentError('No patient with id ${patient.id}');
    }
    _patients[patient.id] = patient;
    return patient;
  }

  @override
  Future<void> deletePatient(String id) async {
    _patients.remove(id);
  }

  @override
  Future<Patient> updatePrescription(String patientId, GamePrescription prescription) async {
    final patient = _patients[patientId];
    if (patient == null) {
      throw ArgumentError('No patient with id $patientId');
    }
    final updatedPrescriptions = Map<GameType, GamePrescription>.from(patient.prescriptions);
    updatedPrescriptions[prescription.type] = prescription;
    final updatedPatient = patient.copyWith(prescriptions: updatedPrescriptions);
    _patients[patientId] = updatedPatient;
    return updatedPatient;
  }

  @override
  Future<Patient> updateCalibration(String patientId, Map<String, dynamic> calibration) async {
    final patient = _patients[patientId];
    if (patient == null) {
      throw ArgumentError('No patient with id $patientId');
    }
    final updatedPatient = patient.copyWith(calibration: calibration);
    _patients[patientId] = updatedPatient;
    return updatedPatient;
  }
}
