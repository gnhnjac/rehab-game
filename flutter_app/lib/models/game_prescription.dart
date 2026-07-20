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
  final int difficulty;

  const CubesBoxesPrescription({
    required super.cycles,
    required this.timerSeconds,
    this.difficulty = 2,
  }) : super(type: GameType.cubesBoxes);

  CubesBoxesPrescription copyWith({
    int? cycles,
    int? timerSeconds,
    int? difficulty,
  }) {
    return CubesBoxesPrescription(
      cycles: cycles ?? this.cycles,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  factory CubesBoxesPrescription.fromJson(Map<String, dynamic> json) {
    return CubesBoxesPrescription(
      cycles: json['cycles'] as int,
      timerSeconds: json['timerSeconds'] as int,
      difficulty: json['difficulty'] as int? ?? 2,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'cubesBoxes',
        'cycles': cycles,
        'timerSeconds': timerSeconds,
        'difficulty': difficulty,
      };
}

final class PinchPrescription extends GamePrescription {
  final int holdDurationSeconds;

  const PinchPrescription({
    required super.cycles,
    required this.holdDurationSeconds,
  }) : super(type: GameType.pinch);

  PinchPrescription copyWith({
    int? cycles,
    int? holdDurationSeconds,
  }) {
    return PinchPrescription(
      cycles: cycles ?? this.cycles,
      holdDurationSeconds: holdDurationSeconds ?? this.holdDurationSeconds,
    );
  }

  factory PinchPrescription.fromJson(Map<String, dynamic> json) {
    return PinchPrescription(
      cycles: json['cycles'] as int,
      holdDurationSeconds: json['holdDurationSeconds'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'pinch',
        'cycles': cycles,
        'holdDurationSeconds': holdDurationSeconds,
      };
}

final class BendPrescription extends GamePrescription {
  final int holdDurationSeconds;
  final List<bool> activeFingers;
  final List<int> sequence;
  final List<int> fingerRomTargets;

  const BendPrescription({
    required super.cycles,
    required this.holdDurationSeconds,
    this.activeFingers = const [true, true, true, true, true],
    this.sequence = const [1, 2, 3, 4, 5],
    this.fingerRomTargets = const [70, 70, 70, 70, 70],
  }) : super(type: GameType.bend);

  double get targetRomPercent =>
      (fingerRomTargets.isNotEmpty ? fingerRomTargets.first : 70).toDouble();

  BendPrescription copyWith({
    int? cycles,
    int? holdDurationSeconds,
    List<bool>? activeFingers,
    List<int>? sequence,
    List<int>? fingerRomTargets,
  }) {
    return BendPrescription(
      cycles: cycles ?? this.cycles,
      holdDurationSeconds: holdDurationSeconds ?? this.holdDurationSeconds,
      activeFingers: activeFingers ?? this.activeFingers,
      sequence: sequence ?? this.sequence,
      fingerRomTargets: fingerRomTargets ?? this.fingerRomTargets,
    );
  }

  factory BendPrescription.fromJson(Map<String, dynamic> json) {
    final activeFingersRaw = json['activeFingers'] as List?;
    final activeFingers = activeFingersRaw != null
        ? activeFingersRaw.map((e) => e as bool).toList()
        : const [true, true, true, true, true];

    final sequenceRaw = json['sequence'] as List?;
    final sequence = sequenceRaw != null
        ? sequenceRaw.map((e) => (e as num).toInt()).toList()
        : const [1, 2, 3, 4, 5];

    final fingerRomTargetsRaw = json['fingerRomTargets'] as List?;
    List<int> fingerRomTargets;
    if (fingerRomTargetsRaw != null) {
      fingerRomTargets =
          fingerRomTargetsRaw.map((e) => (e as num).toInt()).toList();
    } else {
      final legacyRom = (json['targetRomPercent'] as num? ?? 70).toInt();
      fingerRomTargets = List.filled(5, legacyRom);
    }

    return BendPrescription(
      cycles: json['cycles'] as int,
      holdDurationSeconds: json['holdDurationSeconds'] as int,
      activeFingers: activeFingers,
      sequence: sequence,
      fingerRomTargets: fingerRomTargets,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bend',
        'cycles': cycles,
        'holdDurationSeconds': holdDurationSeconds,
        'targetRomPercent': targetRomPercent,
        'activeFingers': activeFingers,
        'sequence': sequence,
        'fingerRomTargets': fingerRomTargets,
      };
}
