import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/glove_telemetry.dart';
import 'telemetry_service.dart';

class DirectTelemetryService implements TelemetryService {
  String gloveHost = 'rehab-glove.local';
  Timer? _pollingTimer;
  bool _isConnected = false;
  bool _isPolling = false;
  int _failureCount = 0;
  
  final StreamController<GloveTelemetry> _controller = StreamController<GloveTelemetry>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  @override
  Stream<GloveTelemetry> get telemetryStream => _controller.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  bool get isConnected => _isConnected;

  void setHost(String host) {
    if (host.trim().isEmpty) return;
    gloveHost = host.trim();
    _logController.add("[DirectTelemetry] Host updated to: $gloveHost");
  }

  @override
  Future<void> connect() async {
    if (_pollingTimer != null) return;
    
    _logController.add("[DirectTelemetry] Connecting to Glove at http://$gloveHost...");
    _failureCount = 0;
    
    // Start polling at 4Hz (250ms) to reduce CPU load on ESP32 WebServer
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      if (_isPolling) return; // Prevent overlapping requests
      _isPolling = true;
      await _pollTelemetry();
      _isPolling = false;
    });
  }

  Future<void> _pollTelemetry() async {
    try {
      final uri = Uri.parse('http://$gloveHost/api/telemetry');
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        _failureCount = 0; // Reset consecutive failure counter
        if (!_isConnected) {
          _isConnected = true;
          _logController.add("[DirectTelemetry] Connected to Glove at $gloveHost");
        }
        
        final Map<String, dynamic> json = jsonDecode(response.body);
        final telemetry = GloveTelemetry.fromJson(json);
        _controller.add(telemetry);
      } else {
        _failureCount++;
        if (_failureCount >= 3) {
          _handleDisconnect("HTTP error: ${response.statusCode}");
        }
      }
    } catch (e) {
      _failureCount++;
      if (_failureCount >= 3) {
        _handleDisconnect(e.toString());
      }
    }
  }

  void _handleDisconnect(String reason) {
    if (_isConnected) {
      _isConnected = false;
      _logController.add("[DirectTelemetry] Disconnected from Glove (after 3 consecutive failures): $reason");
      _controller.add(GloveTelemetry.uncalibrated());
    }
  }

  Future<bool> sendCommand(String cmd, int time) async {
    try {
      final uri = Uri.parse('http://$gloveHost/api/command?cmd=$cmd&time=$time');
      _logController.add("[DirectTelemetry] Sending command: $cmd with time $time to $uri");
      final response = await http.post(uri).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        _logController.add("[DirectTelemetry] Command sent successfully: ${response.body}");
        return true;
      } else {
        _logController.add("[DirectTelemetry] Command failed: HTTP ${response.statusCode}");
        return false;
      }
    } catch (e) {
      _logController.add("[DirectTelemetry] Command error: $e");
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isConnected = false;
    _logController.add("[DirectTelemetry] Disconnected.");
  }
}
