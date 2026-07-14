import 'telemetry_service.dart';
import 'direct_telemetry_service.dart';

class TelemetryProvider {
  static DirectTelemetryService? _instance;

  /// Factory method to retrieve the active direct telemetry service.
  static TelemetryService getService() {
    _instance ??= DirectTelemetryService();
    return _instance!;
  }
}
