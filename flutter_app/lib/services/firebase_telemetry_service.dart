import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/glove_telemetry.dart';
import 'telemetry_service.dart';

class FirebaseTelemetryService implements TelemetryService {
  StreamSubscription? _dbSubscription;
  bool _isConnected = false;

  final StreamController<GloveTelemetry> _controller = StreamController<GloveTelemetry>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

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
      _logController.add("[FirebaseTelemetry] Connecting to Firebase Realtime Database...");
      final dbRef = FirebaseDatabase.instance.ref('telemetry');
      
      _dbSubscription = dbRef.onValue.listen((DatabaseEvent event) {
        final data = event.snapshot.value;
        _logController.add("[FirebaseTelemetry] Snapshot received");
        
        if (data != null) {
          try {
            final mappedData = Map<String, dynamic>.from(
              (data as Map).map((key, value) => MapEntry(key.toString(), value))
            );
            final telemetry = GloveTelemetry.fromJson(mappedData);
            _controller.add(telemetry);
          } catch (e) {
            _logController.add("[FirebaseTelemetry] JSON parsing error: $e");
          }
        } else {
          _logController.add("[FirebaseTelemetry] No telemetry data found at database path.");
          _controller.add(GloveTelemetry.uncalibrated());
        }
      }, onError: (err) {
        _logController.add("[FirebaseTelemetry] Database listener error: $err");
        _controller.addError(err);
      });
      
      _isConnected = true;
      _logController.add("[FirebaseTelemetry] Connected & Listening to '/telemetry' node.");
    } catch (e) {
      _logController.add("[FirebaseTelemetry] Connection failed: $e");
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    await _dbSubscription?.cancel();
    _dbSubscription = null;
    _logController.add("[FirebaseTelemetry] Unsubscribed and disconnected.");
  }
}
