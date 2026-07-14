import 'game_prescription.dart';

class Patient {
  final String id;
  final String name;
  final int? age;
  final String? notes;
  final Map<GameType, GamePrescription> prescriptions;
  final Map<String, dynamic> calibration;

  const Patient({
    required this.id,
    required this.name,
    this.age,
    this.notes,
    required this.prescriptions,
    required this.calibration,
  });

  Patient copyWith({
    String? name,
    int? age,
    String? notes,
    Map<GameType, GamePrescription>? prescriptions,
    Map<String, dynamic>? calibration,
  }) {
    return Patient(
      id: id,
      name: name ?? this.name,
      age: age ?? this.age,
      notes: notes ?? this.notes,
      prescriptions: prescriptions ?? this.prescriptions,
      calibration: calibration ?? this.calibration,
    );
  }
}
