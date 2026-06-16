import 'telemetry_service.dart';
import 'firebase_telemetry_service.dart';

class TelemetryProvider {
  /// Factory method to retrieve the active Firebase telemetry service.
  static TelemetryService getService() {
    return FirebaseTelemetryService();
  }
}
