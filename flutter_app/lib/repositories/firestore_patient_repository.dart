import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
      difficulty: (cb['difficulty'] as num? ?? 2).toInt(),
    );

    // 2. Pinch
    final pinch = rxData['pinch'] as Map<String, dynamic>? ?? {};
    prescriptionsMap[GameType.pinch] = PinchPrescription(
      cycles: (pinch['cycles'] as num? ?? 10).toInt(),
      holdDurationSeconds: (pinch['requiredHoldTimeSeconds'] as num? ?? 5).toInt(),
    );

    // 3. Bend
    final bend = rxData['bend'] as Map<String, dynamic>? ?? {};
    final romList = bend['requiredRom'] as List?;
    final List<int> fingerRomTargets = romList != null
        ? romList.map((e) => (e as num).toInt()).toList()
        : List.filled(5, 70);
    final activeFingersList = bend['activeFingers'] as List?;
    final List<bool> activeFingers = activeFingersList != null
        ? activeFingersList.map((e) => e as bool).toList()
        : List.filled(5, true);
    final sequenceList = bend['sequence'] as List?;
    final List<int> sequence = sequenceList != null
        ? sequenceList.map((e) => (e as num).toInt()).toList()
        : const [1, 2, 3, 4, 5];

    prescriptionsMap[GameType.bend] = BendPrescription(
      cycles: (bend['cycles'] as num? ?? 10).toInt(),
      holdDurationSeconds: (bend['allowedTimeSeconds'] as num? ?? 5).toInt(),
      activeFingers: activeFingers,
      sequence: sequence,
      fingerRomTargets: fingerRomTargets,
    );

    // Parse calibration
    final calibration = data['calibration'] as Map<String, dynamic>? ?? {};
    final parsedCalibration = {
      'flex_min': (calibration['flex_min'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [0, 0, 0, 0, 0],
      'flex_max': (calibration['flex_max'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [4095, 4095, 4095, 4095, 4095],
      'fo_min': (calibration['fo_min'] as num? ?? 4095).toInt(),
      'fo_max': (calibration['fo_max'] as num? ?? 0).toInt(),
    };

    final activeCubeUids = (data['activeCubeUids'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];

    return Patient(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed',
      age: data['age'] as int?,
      notes: data['notes'] as String?,
      prescriptions: prescriptionsMap,
      calibration: parsedCalibration,
      activeCubeUids: activeCubeUids,
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
        'fo_min': 4095,
        'fo_max': 0,
      },
      'activeCubeUids': <String>[],
      'prescription': {
        'cubesBoxes': {
          'timer': 60,
          'cycles': 3,
        },
        'pinch': {
          'requiredHoldTimeSeconds': 5,
        },
        'bend': {
          'allowedTimeSeconds': 5,
          'requiredRom': [70, 70, 70, 70, 70],
        }
      }
    });

    final doc = await docRef.get();
    return _mapDocToPatient(doc);
  }

  @override
  Future<Patient> updatePatient(Patient patient) async {
    await _db.collection('patients').doc(patient.id).update({
      'name': patient.name,
      'age': patient.age,
      'notes': patient.notes,
      'activeCubeUids': patient.activeCubeUids,
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
        'difficulty': prescription.difficulty,
      };
    } else if (prescription is PinchPrescription) {
      updateMap['prescription.pinch'] = {
        'cycles': prescription.cycles,
        'requiredHoldTimeSeconds': prescription.holdDurationSeconds,
      };
    } else if (prescription is BendPrescription) {
      updateMap['prescription.bend'] = {
        'cycles': prescription.cycles,
        'allowedTimeSeconds': prescription.holdDurationSeconds,
        'requiredRom': prescription.fingerRomTargets,
        'activeFingers': prescription.activeFingers,
        'sequence': prescription.sequence,
      };
    }

    await _db.collection('patients').doc(patientId).update(updateMap);
    final doc = await _db.collection('patients').doc(patientId).get();
    return _mapDocToPatient(doc);
  }

  @override
  Future<Patient> updateCalibration(String patientId, Map<String, dynamic> calibration) async {
    debugPrint("Firestore WRITE: collection('patients').doc('$patientId').update({'calibration': $calibration})");
    await _db.collection('patients').doc(patientId).update({
      'calibration': calibration,
    });
    final doc = await _db.collection('patients').doc(patientId).get();
    return _mapDocToPatient(doc);
  }
}
