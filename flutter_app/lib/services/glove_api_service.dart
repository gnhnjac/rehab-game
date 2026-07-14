import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/game_prescription.dart';
import 'direct_telemetry_service.dart';
import 'telemetry_provider.dart';

/// Thin wrapper over the Glove's local REST API (offline-capable).
///
/// Shares the same host as [DirectTelemetryService] (the live telemetry
/// poller) so that changing the glove host in one place affects both.
/// Endpoints are defined in ESP32/glove/glove_web_server.h.
class GloveApiService {
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
        await http.get(_uri('/api/raw-sensors')).timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw GloveApiException('raw-sensors HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final flexRaw = (json['flexRaw'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];
    final forceRaw = (json['forceRaw'] as num?)?.toInt() ?? 0;
    return RawSensors(flexRaw: flexRaw, forceRaw: forceRaw);
  }

  /// POST /api/calibrate-sensor?sensorType=force&coefficients=r0,r1,r2,g0,g1,g2
  ///
  /// The three (raw, grams) points define a piecewise interpolation curve the
  /// firmware uses to map raw ADC readings to grams.
  Future<void> calibrateForce(List<CalibrationPoint> points) async {
    if (points.length != 3) {
      throw GloveApiException('Force calibration requires exactly 3 points');
    }
    final sorted = [...points]..sort((a, b) => a.raw.compareTo(b.raw));
    final coeffs = [
      sorted[0].raw, sorted[1].raw, sorted[2].raw,
      sorted[0].grams.round(), sorted[1].grams.round(), sorted[2].grams.round(),
    ].join(',');
    final response = await http
        .post(_uri('/api/calibrate-sensor', {'sensorType': 'force', 'coefficients': coeffs}))
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
    final response = await http
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
    final response = await http
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
    List<GloveCube> cubes = const [],
  }) async {
    final query = <String, String>{
      'gameType': '${prescription.type.index + 1}',
      'cycles': '${prescription.cycles}',
      'difficulty': '2',
    };


    switch (prescription) {
      case CubesBoxesPrescription p:
        query['timer'] = '${p.timerSeconds}';
        query['targetWeight'] = '${p.targetWeightGrams.round()}';
        if (cubes.isNotEmpty) {
          query['cubes'] = cubes
              .map((c) => '${c.uid}:${c.color}:${c.shape}:${c.weightGrams}')
              .join(',');
        }
      case PinchPrescription p:
        query['holdTime'] = '${p.holdDurationSeconds}';
        query['targetWeight'] = '${p.targetForceGrams.round()}';
      case BendPrescription p:
        query['holdTime'] = '${p.holdDurationSeconds}';
        // Broadcast the ROM target across all 5 fingers.
        query['requiredRom'] =
            List.filled(5, p.targetRomPercent.round()).join(',');
        query['activeFingers'] = '11111';
    }

    if (patientId != null && patientId.isNotEmpty) {
      query['patientId'] = patientId;
    }

    final response = await http
        .post(_uri('/api/active-prescription', query))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw GloveApiException('active-prescription failed: HTTP ${response.statusCode} ${response.body}');
    }
  }
}

class RawSensors {
  final List<int> flexRaw;
  final int forceRaw;
  RawSensors({required this.flexRaw, required this.forceRaw});
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
