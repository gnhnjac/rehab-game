import 'mock_patient_repository.dart';
import 'patient_repository.dart';

class PatientRepositoryProvider {
  static PatientRepository? _instance;

  /// Returns the shared repository instance for the app session.
  /// Swap the implementation constructed here to move to a real
  /// Firestore-backed repository once the schema is finalized.
  static PatientRepository getRepository() {
    return _instance ??= MockPatientRepository();
  }
}
