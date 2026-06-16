import 'dart:async';
import '../models/glove_telemetry.dart';

abstract class TelemetryService {
  /// Stream that emits telemetry data when received.
  Stream<GloveTelemetry> get telemetryStream;

  /// Stream that emits raw log lines for debugging.
  Stream<String> get logStream;

  /// Check if the service is currently connected to the telemetry source.
  bool get isConnected;

  /// Establish connection to the telemetry source.
  Future<void> connect();

  /// Close connection to the telemetry source.
  Future<void> disconnect();
}
