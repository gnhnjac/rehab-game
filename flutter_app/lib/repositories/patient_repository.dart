import '../models/game_prescription.dart';
import '../models/patient.dart';

abstract class PatientRepository {
  Future<List<Patient>> getAllPatients();

  Future<Patient?> getPatientById(String id);

  Future<Patient> addPatient({required String name, int? age, String? notes});

  Future<Patient> updatePatient(Patient patient);

  Future<void> deletePatient(String id);

  Future<Patient> updatePrescription(String patientId, GamePrescription prescription);
}
