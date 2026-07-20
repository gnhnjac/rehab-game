import 'package:firebase_core/firebase_core.dart';
import 'firestore_patient_repository.dart';
import 'mock_patient_repository.dart';
import 'patient_repository.dart';

class PatientRepositoryProvider {
  static PatientRepository? _instance;

  static PatientRepository getRepository() {
    if (_instance != null) return _instance!;
    
    try {
      if (Firebase.apps.isNotEmpty) {
        return _instance = FirestorePatientRepository();
      }
    } catch (_) {}
    
    return _instance = MockPatientRepository();
  }
}

