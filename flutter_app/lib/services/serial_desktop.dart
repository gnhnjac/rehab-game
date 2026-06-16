import 'dart:async';
import 'dart:convert';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../models/glove_telemetry.dart';
import 'telemetry_service.dart';

class SerialTelemetryService implements TelemetryService {
  final String portName;
  final int baudRate;

  SerialPort? _port;
  SerialPortReader? _reader;
  bool _isConnected = false;

  final StreamController<GloveTelemetry> _controller = StreamController<GloveTelemetry>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();
  StreamSubscription? _subscription;
  String _buffer = '';

  SerialTelemetryService({
    required this.portName,
    this.baudRate = 115200,
  });

  @override
  Stream<GloveTelemetry> get telemetryStream => _controller.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        throw Exception("Failed to open serial port $portName");
      }

      // Set baud rate configurations
      _port!.config.baudRate = baudRate;
      _isConnected = true;

      // Listen to incoming stream using flutter_libserialport reader
      _reader = SerialPortReader(_port!);
      _subscription = _reader!.stream.listen(
        _handleIncomingData,
        onError: (err) {
          disconnect();
          _controller.addError(err);
          _logController.addError(err);
        },
        onDone: () => disconnect(),
      );
    } catch (e) {
      disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    await _subscription?.cancel();
    _subscription = null;
    _reader = null;

    try {
      _port?.close();
    } catch (_) {}
    _port = null;
    _buffer = '';
  }

  void _handleIncomingData(List<int> bytes) {
    // Decode UTF-8 string data, allowing malformed data chunks
    final data = utf8.decode(bytes, allowMalformed: true);
    _buffer += data;

    // Process all full lines received
    while (_buffer.contains('\n')) {
      final index = _buffer.indexOf('\n');
      final line = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);

      if (line.isEmpty) continue;

      if (line.startsWith('JSON:')) {
        try {
          final jsonStr = line.substring(5);
          final telemetryMap = jsonDecode(jsonStr) as Map<String, dynamic>;
          final telemetry = GloveTelemetry.fromJson(telemetryMap);
          _controller.add(telemetry);
        } catch (e) {
          // Ignore parse errors from partial or corrupted serial packets
        }
      } else {
        // Forward standard log output
        _logController.add(line);
      }
    }
  }
}
