import 'telemetry_service.dart';
import 'serial_telemetry_service.dart';
import 'firebase_telemetry_service.dart';

enum TelemetrySource { serial, firebase }

class TelemetryProvider {
  /// Factory method to retrieve the active telemetry service source.
  /// 
  /// Toggle `source` to swap between Serial and Firebase backends instantly.
  static TelemetryService getService(TelemetrySource source, {String serialPort = 'COM3'}) {
    switch (source) {
      case TelemetrySource.serial:
        return SerialTelemetryService(portName: serialPort);
      case TelemetrySource.firebase:
        return FirebaseTelemetryService();
    }
  }
}
