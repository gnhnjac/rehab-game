import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  FirestoreService() {
    // Configure offline persistence
    _db.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // --- Patients Operations ---

  /// Stream of all patients, ordered by creation date
  Stream<List<Map<String, dynamic>>> streamPatients() {
    return _db
        .collection('patients')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Create a new patient profile
  Future<String> addPatient(String name) async {
    final docRef = await _db.collection('patients').add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
      'calibration': {
        'fsr_coef_a': 0.0,
        'fsr_coef_b': 0.0,
        'fsr_coef_c': 0.0,
        'flex_min': [0, 0, 0, 0, 0],
        'flex_max': [4095, 4095, 4095, 4095, 4095],
      },
      'prescription': {
        'cubesBoxes': {
          'timer': 60,
          'cycles': 3,
          'allowedWeightsGrams': [100, 500],
          'difficulty': 2,
        },
        'pinch': {
          'targetWeightGrams': 100,
          'requiredHoldTimeSeconds': 5,
          'activeFingers': [1, 2],
        },
        'bend': {
          'allowedTimeSeconds': 30,
          'sequence': [1, 2, 3, 4, 5],
          'requiredRom': [80, 80, 80, 80, 80],
        }
      }
    });
    return docRef.id;
  }

  /// Update calibration coefficients for a patient
  Future<void> updatePatientCalibration(String patientId, Map<String, dynamic> calibration) async {
    await _db.collection('patients').doc(patientId).update({
      'calibration': calibration,
    });
  }

  /// Update prescription parameters for a patient
  Future<void> updatePatientPrescription(String patientId, Map<String, dynamic> prescription) async {
    await _db.collection('patients').doc(patientId).update({
      'prescription': prescription,
    });
  }

  // --- Game History Operations ---

  /// Log a completed game session
  Future<void> addGameHistory({
    required String patientId,
    required String gameType,
    required int successCount,
    required int totalCycles,
    required Map<String, dynamic> metrics,
  }) async {
    await _db.collection('game_history').add({
      'patientId': patientId,
      'gameType': gameType,
      'timestamp': FieldValue.serverTimestamp(),
      'successCount': successCount,
      'totalCycles': totalCycles,
      'metrics': metrics,
    });
  }

  /// Stream of game history logs for a specific patient
  Stream<List<Map<String, dynamic>>> streamGameHistory(String patientId) {
    return _db
        .collection('game_history')
        .where('patientId', isEqualTo: patientId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // --- Cubes & Boxes Registry Operations ---

  /// Register or update an interactive NFC Cube
  Future<void> saveCube({
    required String uid,
    required String name,
    required String color,
    required String shape,
    required int weightGrams,
  }) async {
    await _db.collection('cubes').doc(uid).set({
      'name': name,
      'color': color,
      'shape': shape,
      'weightGrams': weightGrams,
    });
  }

  /// Stream of all registered cubes
  Stream<List<Map<String, dynamic>>> streamCubes() {
    return _db.collection('cubes').snapshots().map((snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          data['uid'] = doc.id;
          return data;
        }).toList());
  }

  /// Register or update a Smart Box by MAC address
  Future<void> saveBox({
    required String macAddress,
    required String name,
    required String shape,
  }) async {
    await _db.collection('boxes').doc(macAddress).set({
      'name': name,
      'shape': shape,
    });
  }

  /// Stream of all registered boxes
  Stream<List<Map<String, dynamic>>> streamBoxes() {
    return _db.collection('boxes').snapshots().map((snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          data['macAddress'] = doc.id;
          return data;
        }).toList());
  }
}
