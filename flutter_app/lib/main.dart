import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'repositories/patient_repository_provider.dart';
import 'screens/patient_list_screen.dart';
import 'screens/exercise_control_screen.dart';
import 'models/game_prescription.dart';
import 'services/cube_registry.dart';
import 'services/box_registry.dart';
import 'services/telemetry_provider.dart';
import 'state/app_state.dart';
import 'state/app_state_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  FirebaseOptions? options;
  try {
    final configString = await rootBundle.loadString('assets/firebase_config.json');
    final config = jsonDecode(configString);
    if (config['apiKey'] != "YOUR_API_KEY") {
      options = FirebaseOptions(
        apiKey: config['apiKey'] ?? '',
        authDomain: config['authDomain'] ?? '',
        databaseURL: config['databaseURL'] ?? '',
        projectId: config['projectId'] ?? '',
        storageBucket: config['storageBucket'] ?? '',
        messagingSenderId: config['messagingSenderId'] ?? '',
        appId: config['appId'] ?? '',
      );
    }
  } catch (e) {
    debugPrint("Failed to load Firebase config from assets: $e");
  }

  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
      // Initialize registries for background Cloud Firestore syncing
      await CubeRegistry.load();
      await BoxRegistry.load();
    } catch (e) {
      debugPrint("Firebase init error: $e");
    }
  }
  runApp(const RehabGloveApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class RehabGloveApp extends StatefulWidget {
  const RehabGloveApp({super.key});

  @override
  State<RehabGloveApp> createState() => _RehabGloveAppState();
}

class _RehabGloveAppState extends State<RehabGloveApp> {
  StreamSubscription? _telemetrySub;

  @override
  void initState() {
    super.initState();
    _startGlobalTelemetryListener();
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    super.dispose();
  }

  void _startGlobalTelemetryListener() {
    final service = TelemetryProvider.getService();
    _telemetrySub = service.telemetryStream.listen((t) {
      if (t.sessionActive && !ExerciseControlScreen.isActive) {
        final context = navigatorKey.currentContext;
        if (context != null) {
          final appState = AppStateScope.of(context);
          final activePatient = appState.activePatient;
          if (activePatient != null && t.gameType >= 1 && t.gameType <= 3) {
            final gameType = GameType.values[t.gameType - 1];
            final prescription = activePatient.prescriptions[gameType];
            if (prescription != null) {
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => ExerciseControlScreen(
                    patientId: activePatient.id,
                    patientName: activePatient.name,
                    prescription: prescription,
                  ),
                ),
              );
            }
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: AppState(repository: PatientRepositoryProvider.getRepository())..loadPatients(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Rehab Glove Hub',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0D0E15),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF8B5CF6),      // Cyber Purple
            secondary: Color(0xFF10B981),    // Neon Emerald
            surface: Color(0xFF141722),
            background: Color(0xFF0D0E15),
            error: Color(0xFFEF4444),
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF141722),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF232A3D), width: 1),
            ),
            elevation: 8,
          ),
        ),
        home: const PatientListScreen(),
      ),
    );
  }
}
