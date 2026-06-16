import 'dart:async';
import '../models/glove_telemetry.dart';
import 'telemetry_service.dart';

/// A blueprint class for later swapping to Firebase Database.
/// 
/// To enable this service:
/// 1. Add packages to pubspec.yaml:
///    - `firebase_core`
///    - `firebase_database` (or `cloud_firestore`)
/// 2. Uncomment the Firebase references and imports.
class FirebaseTelemetryService implements TelemetryService {
  // DatabaseReference? _dbRef;
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
      // --- FUTURE FIREBASE IMPLEMENTATION ---
      // 
      // // Point to the telemetry location in Firebase RTDB
      // _dbRef = FirebaseDatabase.instance.ref('telemetry/glove_status');
      // 
      // // Listen to real-time value changes
      // _dbSubscription = _dbRef!.onValue.listen((DatabaseEvent event) {
      //   final data = event.snapshot.value as Map<dynamic, dynamic>?;
      //   if (data != null) {
      //     // Convert map types and deserialize JSON
      //     final mappedData = Map<String, dynamic>.from(
      //       data.map((key, value) => MapEntry(key.toString(), value))
      //     );
      //     final telemetry = GloveTelemetry.fromJson(mappedData);
      //     _controller.add(telemetry);
      //   }
      // }, onError: (err) {
      //   _controller.addError(err);
      // });
      
      _isConnected = true;
      print("[FirebaseTelemetry] Subscribed to Realtime Database endpoint.");
    } catch (e) {
      disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    await _dbSubscription?.cancel();
    _dbSubscription = null;
    print("[FirebaseTelemetry] Unsubscribed and disconnected.");
  }
}
