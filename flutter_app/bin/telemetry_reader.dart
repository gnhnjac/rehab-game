import 'dart:convert';
import 'dart:io';
import '../lib/models/glove_telemetry.dart';

void main() async {
  // Disable console buffer line wrapping for cleaner UI if supported
  print('\x1B[2J\x1B[H'); // Clear console
  print('=====================================================');
  print('   REHAB GLOVE DART TELEMETRY CLI READER READY       ');
  print('=====================================================');
  print('To test, pipe in your Glove serial output or paste a JSON line.');
  print('Format: JSON:{"flex":[50,60,70,80,90],"force":45,"calibrated":true,"boxes":[]}');
  print('Press Ctrl+C to exit.\n');

  // Read lines from standard input
  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (line.startsWith('JSON:')) {
      try {
        final jsonStr = line.substring(5).trim();
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        final telemetry = GloveTelemetry.fromJson(map);

        _renderTelemetry(telemetry);
      } catch (e) {
        print('Error parsing telemetry JSON: $e');
      }
    } else {
      // Print regular Glove logs
      print('[Glove Log] $line');
    }
  });
}

void _renderTelemetry(GloveTelemetry data) {
  if (!data.calibrated) {
    print('\x1B[2J\x1B[H'); // Clear console
    print('=====================================================');
    print('  GLOVE STATUS: AWAITING CALIBRATION...              ');
    print('=====================================================');
    print('Please press the calibration button (GPIO 4) on your Glove.');
    return;
  }

  print('\x1B[2J\x1B[H'); // Clear console
  print('=====================================================');
  print('          GLOVE REHAB TELEMETRY DASHBOARD            ');
  print('=====================================================');
  
  // Render Flex percentage bars
  print('Flex Sensors:');
  for (int i = 0; i < data.flex.length; i++) {
    final value = data.flex[i];
    final activeSegments = (value / 5).round();
    final bar = '=' * activeSegments + ' ' * (20 - activeSegments);
    print('  Finger ${i + 1}: [${bar}] $value%');
  }

  print('-----------------------------------------------------');
  // Render Force FSR percentage bar
  final forceValue = data.force;
  final forceSegments = (forceValue / 5).round();
  final forceBar = '=' * forceSegments + ' ' * (20 - forceSegments);
  print('  Force FSR: [${forceBar}] $forceValue%');
  print('-----------------------------------------------------');

  // Render registered smart boxes
  print('Connected Smart Boxes:');
  if (data.boxes.isEmpty) {
    print('  [No boxes registered. Waiting for box pair...]');
  } else {
    for (var box in data.boxes) {
      final cubeStr = box.isCubePresent ? "Cube UID: ${box.cubeUid}" : "[EMPTY]";
      print('  ● Box [${box.mac}] -> $cubeStr');
    }
  }
  print('=====================================================\n');
}
