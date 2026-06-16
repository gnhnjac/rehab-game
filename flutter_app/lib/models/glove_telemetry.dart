class BoxTelemetry {
  final String mac;
  final String cubeUid;

  BoxTelemetry({
    required this.mac,
    required this.cubeUid,
  });

  bool get isCubePresent => cubeUid.isNotEmpty;

  factory BoxTelemetry.fromJson(Map<String, dynamic> json) {
    return BoxTelemetry(
      mac: json['mac'] ?? '',
      cubeUid: json['cube'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'mac': mac,
    'cube': cubeUid,
  };
}

class GloveTelemetry {
  final List<int> flex;
  final int force;
  final bool calibrated;
  final List<BoxTelemetry> boxes;

  GloveTelemetry({
    required this.flex,
    required this.force,
    required this.calibrated,
    required this.boxes,
  });

  factory GloveTelemetry.fromJson(Map<String, dynamic> json) {
    return GloveTelemetry(
      flex: List<int>.from(json['flex'] ?? []),
      force: json['force'] ?? 0,
      calibrated: json['calibrated'] ?? false,
      boxes: (json['boxes'] as List? ?? [])
          .map((b) => BoxTelemetry.fromJson(Map<String, dynamic>.from(b)))
          .toList(),
    );
  }

  factory GloveTelemetry.uncalibrated() {
    return GloveTelemetry(
      flex: [],
      force: 0,
      calibrated: false,
      boxes: [],
    );
  }

  Map<String, dynamic> toJson() => {
    'flex': flex,
    'force': force,
    'calibrated': calibrated,
    'boxes': boxes.map((b) => b.toJson()).toList(),
  };
}
