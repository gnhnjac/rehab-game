// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_app/models/glove_telemetry.dart';

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
  for (int i = 0; i < data.flex.percent.length; i++) {
    final value = data.flex.percent[i];
    final rawValue = data.flex.raw.length > i ? data.flex.raw[i] : 0;
    final activeSegments = (value / 5).round();
    final bar = '=' * activeSegments + ' ' * (20 - activeSegments);
    print('  Finger ${i + 1}: [$bar] $value% (Raw: $rawValue)');
  }

  print('-----------------------------------------------------');
  // Render Force FSR percentage bar
  final forceValue = data.force.percent.isNotEmpty ? data.force.percent.first : 0;
  final forceRaw = data.force.raw.isNotEmpty ? data.force.raw.first : 0;
  final forceSegments = (forceValue / 5).round();
  final forceBar = '=' * forceSegments + ' ' * (20 - forceSegments);
  print('  Force FSR: [$forceBar] $forceValue% (Raw: $forceRaw)');
  print('-----------------------------------------------------');

  // Render registered weight movement tracking
  print('Weight Movement Tracking:');
  if (data.boxActions.isEmpty) {
    print('  [No weights registered. Waiting for weight events...]');
  } else {
    for (var action in data.boxActions) {
      final statusStr = action.isPlaced ? "Placed in Box ${action.boxIndex + 1}" : "Picked Up";
      final timeStr = DateTime.fromMillisecondsSinceEpoch(action.timestamp * 1000).toLocal().toString().split('.').first;
      print('  ● Weight [${action.cubeId}] -> $statusStr (Last Event: $timeStr)');
    }
  }
  print('=====================================================\n');
}
