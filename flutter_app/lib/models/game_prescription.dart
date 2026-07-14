enum GameType { cubesBoxes, pinch, bend }

sealed class GamePrescription {
  final GameType type;
  final int cycles;

  const GamePrescription({required this.type, required this.cycles});

  Map<String, dynamic> toJson();

  static GamePrescription fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'cubesBoxes':
        return CubesBoxesPrescription.fromJson(json);
      case 'pinch':
        return PinchPrescription.fromJson(json);
      case 'bend':
        return BendPrescription.fromJson(json);
      default:
        throw FormatException('Unknown GamePrescription type: $type');
    }
  }
}

final class CubesBoxesPrescription extends GamePrescription {
  final int timerSeconds;
  final double targetWeightGrams;
  final int difficulty;

  const CubesBoxesPrescription({
    required super.cycles,
    required this.timerSeconds,
    required this.targetWeightGrams,
    this.difficulty = 2,
  }) : super(type: GameType.cubesBoxes);

  CubesBoxesPrescription copyWith({
    int? cycles,
    int? timerSeconds,
    double? targetWeightGrams,
    int? difficulty,
  }) {
    return CubesBoxesPrescription(
      cycles: cycles ?? this.cycles,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      targetWeightGrams: targetWeightGrams ?? this.targetWeightGrams,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  factory CubesBoxesPrescription.fromJson(Map<String, dynamic> json) {
    return CubesBoxesPrescription(
      cycles: json['cycles'] as int,
      timerSeconds: json['timerSeconds'] as int,
      targetWeightGrams: (json['targetWeightGrams'] as num).toDouble(),
      difficulty: json['difficulty'] as int? ?? 2,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'cubesBoxes',
        'cycles': cycles,
        'timerSeconds': timerSeconds,
        'targetWeightGrams': targetWeightGrams,
        'difficulty': difficulty,
      };
}

final class PinchPrescription extends GamePrescription {
  final int holdDurationSeconds;
  final double targetForceGrams;

  const PinchPrescription({
    required super.cycles,
    required this.holdDurationSeconds,
    required this.targetForceGrams,
  }) : super(type: GameType.pinch);

  PinchPrescription copyWith({
    int? cycles,
    int? holdDurationSeconds,
    double? targetForceGrams,
  }) {
    return PinchPrescription(
      cycles: cycles ?? this.cycles,
      holdDurationSeconds: holdDurationSeconds ?? this.holdDurationSeconds,
      targetForceGrams: targetForceGrams ?? this.targetForceGrams,
    );
  }

  factory PinchPrescription.fromJson(Map<String, dynamic> json) {
    return PinchPrescription(
      cycles: json['cycles'] as int,
      holdDurationSeconds: json['holdDurationSeconds'] as int,
      targetForceGrams: (json['targetForceGrams'] as num).toDouble(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'pinch',
        'cycles': cycles,
        'holdDurationSeconds': holdDurationSeconds,
        'targetForceGrams': targetForceGrams,
      };
}

final class BendPrescription extends GamePrescription {
  final int holdDurationSeconds;
  final double targetRomPercent;

  const BendPrescription({
    required super.cycles,
    required this.holdDurationSeconds,
    required this.targetRomPercent,
  }) : super(type: GameType.bend);

  BendPrescription copyWith({
    int? cycles,
    int? holdDurationSeconds,
    double? targetRomPercent,
  }) {
    return BendPrescription(
      cycles: cycles ?? this.cycles,
      holdDurationSeconds: holdDurationSeconds ?? this.holdDurationSeconds,
      targetRomPercent: targetRomPercent ?? this.targetRomPercent,
    );
  }

  factory BendPrescription.fromJson(Map<String, dynamic> json) {
    return BendPrescription(
      cycles: json['cycles'] as int,
      holdDurationSeconds: json['holdDurationSeconds'] as int,
      targetRomPercent: (json['targetRomPercent'] as num).toDouble(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bend',
        'cycles': cycles,
        'holdDurationSeconds': holdDurationSeconds,
        'targetRomPercent': targetRomPercent,
      };
}
