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
  
  // Shared persistent HTTP client to support HTTP Keep-Alive
  http.Client? _client;
  
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
    _client = http.Client(); // Instantiate persistent client
    
    // Start polling at ~3.3Hz (300ms) for high responsiveness and stability
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (_isPolling) return; // Prevent overlapping requests
      _isPolling = true;
      await _pollTelemetry();
      _isPolling = false;
    });
  }

  void _recreateClient() {
    try {
      _client?.close();
    } catch (_) {}
    _client = http.Client();
  }

  Future<void> _pollTelemetry() async {
    if (_client == null) return;
    try {
      final uri = Uri.parse('http://$gloveHost/api/telemetry');
      // Pass Keep-Alive header to reuse the TCP socket
      final response = await _client!.get(uri, headers: {
        'Connection': 'keep-alive',
      }).timeout(const Duration(milliseconds: 1000));
      
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
        _recreateClient(); // Recreate client on error to discard broken socket
        if (_failureCount >= 5) {
          _handleDisconnect("HTTP error: ${response.statusCode}");
        }
      }
    } catch (e) {
      _failureCount++;
      _recreateClient(); // Recreate client on exception/timeout to discard broken socket
      if (_failureCount >= 5) {
        _handleDisconnect(e.toString());
      }
    }
  }

  void _handleDisconnect(String reason) {
    if (_isConnected) {
      _isConnected = false;
      _logController.add("[DirectTelemetry] Disconnected from Glove (after 5 consecutive failures): $reason");
      _controller.add(GloveTelemetry.uncalibrated());
    }
  }

  Future<bool> sendCommand(String cmd, int time) async {
    if (_client == null) return false;
    try {
      final uri = Uri.parse('http://$gloveHost/api/command?cmd=$cmd&time=$time');
      _logController.add("[DirectTelemetry] Sending command: $cmd with time $time to $uri");
      final response = await _client!.post(uri).timeout(const Duration(seconds: 2));
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
    _client?.close(); // Close connection
    _client = null;
    _isConnected = false;
    _logController.add("[DirectTelemetry] Disconnected.");
  }
}
