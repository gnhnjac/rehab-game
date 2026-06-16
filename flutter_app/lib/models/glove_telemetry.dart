class SensorGroup {
  final List<int> raw;
  final List<int> percent;

  SensorGroup({required this.raw, required this.percent});

  factory SensorGroup.fromJson(Map<String, dynamic> json) {
    List<int> parseList(dynamic val) {
      if (val == null) return [];
      if (val is List) {
        return List<int>.from(val.map((x) => (x as num).toInt()));
      }
      // Handle single value fallback
      return [(val as num).toInt()];
    }

    return SensorGroup(
      raw: parseList(json['raw']),
      percent: parseList(json['percent']),
    );
  }

  Map<String, dynamic> toJson() => {
    'raw': raw,
    'percent': percent,
  };
}

class BoxAction {
  final String cubeId;
  final int timestamp;
  final bool isPlaced; // true = placed (הונח), false = picked up (הורם)
  final int boxIndex; // index of the box (0-indexed)

  BoxAction({
    required this.cubeId,
    required this.timestamp,
    required this.isPlaced,
    required this.boxIndex,
  });

  factory BoxAction.fromJson(String cubeId, dynamic json) {
    if (json is List) {
      // Tuple format: [timestamp, isPlaced, boxIndex]
      return BoxAction(
        cubeId: cubeId,
        timestamp: json.isNotEmpty ? (json[0] as num).toInt() : 0,
        isPlaced: json.length > 1 ? (json[1] is bool ? json[1] as bool : json[1] == 1) : false,
        boxIndex: json.length > 2 ? (json[2] as num).toInt() : 0,
      );
    } else if (json is Map) {
      // Map format fallback
      return BoxAction(
        cubeId: cubeId,
        timestamp: (json['timestamp'] ?? 0) as int,
        isPlaced: (json['isPlaced'] ?? json['flag'] ?? false) as bool,
        boxIndex: (json['boxIndex'] ?? json['box'] ?? 0) as int,
      );
    }
    throw FormatException("Invalid box action format: $json");
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'isPlaced': isPlaced,
    'boxIndex': boxIndex,
  };
}

class GloveTelemetry {
  final bool calibrated;
  final SensorGroup flex;
  final SensorGroup force;
  final List<BoxAction> boxActions;

  GloveTelemetry({
    required this.calibrated,
    required this.flex,
    required this.force,
    required this.boxActions,
  });

  factory GloveTelemetry.fromJson(Map<String, dynamic> json) {
    final flexJson = json['flex'] != null 
        ? Map<String, dynamic>.from(json['flex']) 
        : {'raw': <int>[], 'percent': <int>[]};
    final forceJson = json['force'] != null 
        ? Map<String, dynamic>.from(json['force']) 
        : {'raw': <int>[], 'percent': <int>[]};

    List<BoxAction> boxActionsList = [];
    if (json['weights'] != null) {
      final Map weightsMap = json['weights'] as Map;
      weightsMap.forEach((key, value) {
        boxActionsList.add(BoxAction.fromJson(key.toString(), value));
      });
    }

    return GloveTelemetry(
      calibrated: json['calibrated'] ?? false,
      flex: SensorGroup.fromJson(flexJson),
      force: SensorGroup.fromJson(forceJson),
      boxActions: boxActionsList,
    );
  }

  factory GloveTelemetry.uncalibrated() {
    return GloveTelemetry(
      calibrated: false,
      flex: SensorGroup(raw: [], percent: []),
      force: SensorGroup(raw: [], percent: []),
      boxActions: [],
    );
  }

  Map<String, dynamic> toJson() => {
    'calibrated': calibrated,
    'flex': flex.toJson(),
    'force': force.toJson(),
    'weights': Map.fromEntries(boxActions.map((w) => MapEntry(w.cubeId, w.toJson()))),
  };
}
