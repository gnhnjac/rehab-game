import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/game_prescription.dart';
import '../models/patient.dart';
import 'patient_repository.dart';

class FirestorePatientRepository implements PatientRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Patient _mapDocToPatient(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    // Parse prescriptions
    final prescriptionsMap = <GameType, GamePrescription>{};
    final rxData = data['prescription'] as Map<String, dynamic>? ?? {};

    // 1. Cubes & Boxes
    final cb = rxData['cubesBoxes'] as Map<String, dynamic>? ?? {};
    prescriptionsMap[GameType.cubesBoxes] = CubesBoxesPrescription(
      cycles: (cb['cycles'] as num? ?? 3).toInt(),
      timerSeconds: (cb['timer'] as num? ?? 60).toInt(),
      targetWeightGrams: (cb['targetWeightGrams'] as num? ?? 200.0).toDouble(),
      difficulty: (cb['difficulty'] as num? ?? 2).toInt(),
    );

    // 2. Pinch
    final pinch = rxData['pinch'] as Map<String, dynamic>? ?? {};
    prescriptionsMap[GameType.pinch] = PinchPrescription(
      cycles: (pinch['cycles'] as num? ?? 10).toInt(),
      holdDurationSeconds: (pinch['requiredHoldTimeSeconds'] as num? ?? 5).toInt(),
      targetForceGrams: (pinch['targetWeightGrams'] as num? ?? 500.0).toDouble(),
    );

    // 3. Bend
    final bend = rxData['bend'] as Map<String, dynamic>? ?? {};
    final romList = bend['requiredRom'] as List?;
    final romVal = romList != null && romList.isNotEmpty ? romList.first : 70.0;
    prescriptionsMap[GameType.bend] = BendPrescription(
      cycles: (bend['cycles'] as num? ?? 10).toInt(),
      holdDurationSeconds: (bend['allowedTimeSeconds'] as num? ?? 5).toInt(),
      targetRomPercent: (romVal as num? ?? 70.0).toDouble(),
    );

    // Parse calibration
    final calibration = data['calibration'] as Map<String, dynamic>? ?? {};
    final parsedCalibration = {
      'flex_min': (calibration['flex_min'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [0, 0, 0, 0, 0],
      'flex_max': (calibration['flex_max'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [4095, 4095, 4095, 4095, 4095],
      'fsr_coef_a': (calibration['fsr_coef_a'] as num? ?? 0.0).toDouble(),
      'fsr_coef_b': (calibration['fsr_coef_b'] as num? ?? 0.0).toDouble(),
      'fsr_coef_c': (calibration['fsr_coef_c'] as num? ?? 0.0).toDouble(),
      'fo_min': (calibration['fo_min'] as num? ?? 4095).toInt(),
      'fo_max': (calibration['fo_max'] as num? ?? 0).toInt(),
    };

    return Patient(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed',
      age: data['age'] as int?,
      notes: data['notes'] as String?,
      prescriptions: prescriptionsMap,
      calibration: parsedCalibration,
    );
  }

  @override
  Future<List<Patient>> getAllPatients() async {
    final snapshot = await _db.collection('patients').orderBy('name').get();
    return snapshot.docs.map(_mapDocToPatient).toList();
  }

  @override
  Future<Patient?> getPatientById(String id) async {
    final doc = await _db.collection('patients').doc(id).get();
    if (!doc.exists) return null;
    return _mapDocToPatient(doc);
  }

  @override
  Future<Patient> addPatient({required String name, int? age, String? notes}) async {
    final docRef = await _db.collection('patients').add({
      'name': name,
      'age': age,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'calibration': {
        'flex_min': [0, 0, 0, 0, 0],
        'flex_max': [4095, 4095, 4095, 4095, 4095],
        'fsr_coef_a': 0.0,
        'fsr_coef_b': 0.0,
        'fsr_coef_c': 0.0,
      },
      'prescription': {
        'cubesBoxes': {
          'timer': 60,
          'cycles': 3,
          'targetWeightGrams': 200,
        },
        'pinch': {
          'targetWeightGrams': 500,
          'requiredHoldTimeSeconds': 5,
        },
        'bend': {
          'allowedTimeSeconds': 5,
          'requiredRom': [70, 70, 70, 70, 70],
        }
      }
    });

    final doc = await docRef.get(const GetOptions(source: Source.cache));
    return _mapDocToPatient(doc);
  }

  @override
  Future<Patient> updatePatient(Patient patient) async {
    await _db.collection('patients').doc(patient.id).update({
      'name': patient.name,
      'age': patient.age,
      'notes': patient.notes,
    });
    return patient;
  }

  @override
  Future<void> deletePatient(String id) async {
    await _db.collection('patients').doc(id).delete();
  }

  @override
  Future<Patient> updatePrescription(String patientId, GamePrescription prescription) async {
    Map<String, dynamic> updateMap = {};
    if (prescription is CubesBoxesPrescription) {
      updateMap['prescription.cubesBoxes'] = {
        'cycles': prescription.cycles,
        'timer': prescription.timerSeconds,
        'targetWeightGrams': prescription.targetWeightGrams,
        'difficulty': prescription.difficulty,
      };
    } else if (prescription is PinchPrescription) {
      updateMap['prescription.pinch'] = {
        'cycles': prescription.cycles,
        'requiredHoldTimeSeconds': prescription.holdDurationSeconds,
        'targetWeightGrams': prescription.targetForceGrams,
      };
    } else if (prescription is BendPrescription) {
      updateMap['prescription.bend'] = {
        'cycles': prescription.cycles,
        'allowedTimeSeconds': prescription.holdDurationSeconds,
        'requiredRom': List.filled(5, prescription.targetRomPercent.round()),
      };
    }

    await _db.collection('patients').doc(patientId).update(updateMap);
    final doc = await _db.collection('patients').doc(patientId).get(const GetOptions(source: Source.cache));
    return _mapDocToPatient(doc);
  }

  @override
  Future<Patient> updateCalibration(String patientId, Map<String, dynamic> calibration) async {
    await _db.collection('patients').doc(patientId).update({
      'calibration': calibration,
    });
    final doc = await _db.collection('patients').doc(patientId).get(const GetOptions(source: Source.cache));
    return _mapDocToPatient(doc);
  }
}
