import 'dart:async';
import '../models/glove_telemetry.dart';
import 'telemetry_service.dart';

class SerialTelemetryService implements TelemetryService {
  final String portName;
  final int baudRate;

  SerialTelemetryService({required this.portName, this.baudRate = 115200});

  @override
  Stream<GloveTelemetry> get telemetryStream => throw UnimplementedError("Serial port not supported on this platform.");

  @override
  Stream<String> get logStream => throw UnimplementedError("Serial port not supported on this platform.");

  @override
  bool get isConnected => false;

  @override
  Future<void> connect() async => throw UnimplementedError("Serial port not supported on this platform.");

  @override
  Future<void> disconnect() async {}
}
