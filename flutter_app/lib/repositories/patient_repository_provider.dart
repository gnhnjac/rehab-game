import 'firestore_patient_repository.dart';
import 'patient_repository.dart';

class PatientRepositoryProvider {
  static PatientRepository? _instance;

  static PatientRepository getRepository() {
    return _instance ??= FirestorePatientRepository();
  }
}

