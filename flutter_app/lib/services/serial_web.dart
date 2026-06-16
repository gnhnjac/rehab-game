import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../models/glove_telemetry.dart';
import 'telemetry_service.dart';

@JS('webSerialHelper.isSupported')
external bool jsIsSupported();

@JS('webSerialHelper.requestPort')
external JSPromise<JSObject> jsRequestPort();

@JS('webSerialHelper.openPort')
external JSPromise<JSObject> jsOpenPort(JSObject port, int baudRate);

@JS('webSerialHelper.readChunk')
external JSPromise<JSObject> jsReadChunk(JSObject reader);

@JS('webSerialHelper.closePort')
external JSPromise<JSAny> jsClosePort(JSObject? port, JSObject? reader);

class SerialTelemetryService implements TelemetryService {
  final String portName;
  final int baudRate;

  JSObject? _port;
  JSObject? _reader;
  bool _isConnected = false;
  bool _keepReading = false;

  final StreamController<GloveTelemetry> _controller = StreamController<GloveTelemetry>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();
  String _buffer = '';

  SerialTelemetryService({required this.portName, this.baudRate = 115200});

  @override
  Stream<GloveTelemetry> get telemetryStream => _controller.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    if (!jsIsSupported()) {
      throw Exception("Web Serial API is not supported in this browser. Please use Chrome, Edge, or Opera.");
    }

    try {
      // 1. Request port (shows Chrome's native selection dialog)
      final portObj = await jsRequestPort().toDart;
      _port = portObj;

      // 2. Open port and get reader
      final readerObj = await jsOpenPort(_port!, baudRate).toDart;
      _reader = readerObj;

      _isConnected = true;
      _keepReading = true;

      _logController.add("[WebSerial] Connected successfully.");
      
      // Start asynchronous read loop
      _startReadLoop();
    } catch (e) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _keepReading = false;
    
    _logController.add("[WebSerial] Disconnected.");
    await jsClosePort(_port, _reader).toDart;
    
    _port = null;
    _reader = null;
    _buffer = '';
  }

  void _startReadLoop() async {
    while (_keepReading && _isConnected && _reader != null) {
      try {
        final chunk = await jsReadChunk(_reader!).toDart;

        final JSBoolean? doneJS = chunk.getProperty<JSBoolean>('done'.toJS);
        final bool done = doneJS?.toDart ?? false;
        
        if (done) {
          _logController.add("[WebSerial] Connection closed by device.");
          await disconnect();
          break;
        }

        final JSArray? valueJS = chunk.getProperty<JSArray>('value'.toJS);
        if (valueJS != null) {
          // Convert JSArray to Dart list of numbers
          final List<int> bytes = [];
          for (int i = 0; i < valueJS.length; i++) {
            final JSNumber? num = valueJS.getProperty(i.toJS) as JSNumber?;
            if (num != null) {
              bytes.add(num.toDartDouble.toInt());
            }
          }
          if (bytes.isNotEmpty) {
            _handleIncomingBytes(bytes);
          }
        }
      } catch (e) {
        _logController.add("[WebSerial] Error reading: $e");
        await disconnect();
        break;
      }
    }
  }

  void _handleIncomingBytes(List<int> bytes) {
    final data = utf8.decode(bytes, allowMalformed: true);
    _buffer += data;

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
        _logController.add(line);
      }
    }
  }
}
