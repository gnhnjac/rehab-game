import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/game_prescription.dart';
import 'box_registry.dart';
import 'direct_telemetry_service.dart';
import 'telemetry_provider.dart';

/// Thin wrapper over the Glove's local REST API (offline-capable).
///
/// Shares the same host as [DirectTelemetryService] (the live telemetry
/// poller) so that changing the glove host in one place affects both.
/// Endpoints are defined in ESP32/glove/glove_web_server.h.
class GloveApiService {
  // Shared persistent client to reuse TCP sockets and avoid network saturation
  static final http.Client _httpClient = http.Client();

  /// Resolve the current glove host from the shared telemetry service so the
  /// user only configures it once (in the Config tab / connection panel).
  String get _host {
    final service = TelemetryProvider.getService();
    if (service is DirectTelemetryService) {
      return service.gloveHost;
    }
    return 'rehab-glove.local';
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('http://$_host$path').replace(queryParameters: query);

  /// GET /api/raw-sensors -> {flexRaw:[...], forceRaw:int}
  Future<RawSensors> fetchRawSensors() async {
    final response =
        await _httpClient.get(_uri('/api/raw-sensors')).timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw GloveApiException('raw-sensors HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final flexRaw = (json['flexRaw'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];
    final forceRaw = (json['forceRaw'] as num?)?.toInt() ?? 0;
    final flexMin = (json['flexMin'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];
    final flexMax = (json['flexMax'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];
    return RawSensors(
      flexRaw: flexRaw,
      forceRaw: forceRaw,
      flexMin: flexMin,
      flexMax: flexMax,
    );
  }

  /// POST /api/calibrate-sensor?sensorType=force&forceMin=X&forceMax=Y
  Future<void> calibrateForce({
    required int forceMin,
    required int forceMax,
  }) async {
    final response = await _httpClient
        .post(_uri('/api/calibrate-sensor', {
          'sensorType': 'force',
          'forceMin': '$forceMin',
          'forceMax': '$forceMax',
        }))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw GloveApiException('calibrate force failed: HTTP ${response.statusCode} ${response.body}');
    }
  }

  /// POST /api/calibrate-sensor?sensorType=flex&fingerIndex=N&flexMin=X&flexMax=Y
  Future<void> calibrateFlex({
    required int fingerIndex,
    required int flexMin,
    required int flexMax,
  }) async {
    final response = await _httpClient
        .post(_uri('/api/calibrate-sensor', {
          'sensorType': 'flex',
          'fingerIndex': '$fingerIndex',
          'flexMin': '$flexMin',
          'flexMax': '$flexMax',
        }))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw GloveApiException('calibrate flex failed: HTTP ${response.statusCode} ${response.body}');
    }
  }

  /// GET/POST /api/command?cmd=...&time=...
  Future<void> sendCommand(String cmd, {int time = 0}) async {
    final response = await _httpClient
        .post(_uri('/api/command', {'cmd': cmd, 'time': '$time'}))
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw GloveApiException('command "$cmd" failed: HTTP ${response.statusCode} ${response.body}');
    }
  }

  /// POST /api/active-prescription — pushes a game prescription to the glove
  /// and starts a new game session. Field set mirrors handleActivePrescription
  /// in glove_web_server.h.
  Future<void> sendActivePrescription({
    required GamePrescription prescription,
    String? patientId,
    Map<String, dynamic>? calibration,
    List<GloveCube> cubes = const [],
  }) async {
    int timerSeconds = 60;
    if (prescription is CubesBoxesPrescription) {
      timerSeconds = prescription.timerSeconds;
    } else if (prescription is PinchPrescription) {
      timerSeconds = prescription.cycles * prescription.holdDurationSeconds * 3;
      if (timerSeconds < 120) timerSeconds = 120;
    } else if (prescription is BendPrescription) {
      timerSeconds = prescription.cycles * prescription.holdDurationSeconds * 3;
      if (timerSeconds < 120) timerSeconds = 120;
    }

    final query = <String, String>{
      'gameType': '${prescription.type.index + 1}',
      'cycles': '${prescription.cycles}',
      'timer': '$timerSeconds',
    };

    if (calibration != null) {
      final flexMin = (calibration['flex_min'] as List?)?.map((e) => e.toString()).join(',') ?? '0,0,0,0,0';
      final flexMax = (calibration['flex_max'] as List?)?.map((e) => e.toString()).join(',') ?? '4095,4095,4095,4095,4095';
      final forceMin = calibration['fo_min']?.toString() ?? '4095';
      final forceMax = calibration['fo_max']?.toString() ?? '0';
      
      query['flexMin'] = flexMin;
      query['flexMax'] = flexMax;
      query['forceMin'] = forceMin;
      query['forceMax'] = forceMax;
    }

    switch (prescription) {
      case CubesBoxesPrescription p:
        query['difficulty'] = '${p.difficulty}';
        if (cubes.isNotEmpty) {
          query['cubes'] = cubes
              .map((c) => '${c.uid}:${c.color}:${c.shape}:${c.weightGrams}')
              .join(',');
        }
      case PinchPrescription p:
        query['holdTime'] = '${p.holdDurationSeconds}';
      case BendPrescription p:
        query['holdTime'] = '${p.holdDurationSeconds}';
        query['requiredRom'] = p.fingerRomTargets.join(',');
        query['activeFingers'] =
            p.activeFingers.map((f) => f ? '1' : '0').join('');
        query['sequence'] = p.sequence.join(',');
    }

    if (patientId != null && patientId.isNotEmpty) {
      query['patientId'] = patientId;
    }

    final enrolledBoxes = BoxRegistry.registry.values.toList();
    if (enrolledBoxes.isNotEmpty) {
      query['boxes'] = enrolledBoxes
          .map((b) => '${b.mac.replaceAll(':', '').toUpperCase()}:${b.shape}')
          .join(',');
    }

    final response = await _httpClient
        .post(_uri('/api/active-prescription', query))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw GloveApiException('active-prescription failed: HTTP ${response.statusCode} ${response.body}');
    }
  }

  /// Sends a command to explicitly stop any running prescription game on the glove
  Future<void> stopActivePrescription() async {
    final response = await _httpClient
        .post(_uri('/api/active-prescription', {'gameType': '0'}))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw GloveApiException('stop-prescription failed: HTTP ${response.statusCode} ${response.body}');
    }
  }
}

class RawSensors {
  final List<int> flexRaw;
  final int forceRaw;
  final List<int> flexMin;
  final List<int> flexMax;
  RawSensors({
    required this.flexRaw,
    required this.forceRaw,
    required this.flexMin,
    required this.flexMax,
  });
}

class CalibrationPoint {
  final int raw;
  final double grams;
  CalibrationPoint({required this.raw, required this.grams});
}

class GloveCube {
  final String uid;
  final String color;
  final String shape;
  final int weightGrams;
  GloveCube({
    required this.uid,
    required this.color,
    required this.shape,
    required this.weightGrams,
  });
}

class GloveApiException implements Exception {
  final String message;
  GloveApiException(this.message);
  @override
  String toString() => 'GloveApiException: $message';
}
