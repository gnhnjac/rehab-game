// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/telemetry_provider.dart';
import 'services/telemetry_service.dart';
import 'services/direct_telemetry_service.dart';
import 'services/cube_registry.dart';
import 'models/glove_telemetry.dart';
import 'repositories/patient_repository_provider.dart';
import 'screens/patient_list_screen.dart';
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
    } catch (e) {
      debugPrint("Firebase init error: $e");
    }
  }
  runApp(const RehabGloveApp());
}

class RehabGloveApp extends StatelessWidget {
  const RehabGloveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: AppState(repository: PatientRepositoryProvider.getRepository())..loadPatients(),
      child: MaterialApp(
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum EnrollState { idle, waiting, locking, confirmed }

class _DashboardScreenState extends State<DashboardScreen> {
  TelemetryService? _telemetryService;
  bool _isConnected = false;

  final List<String> _consoleLogs = [];
  final ScrollController _consoleScrollController = ScrollController();
  bool _isConsoleExpanded = true;

  // New features variables
  int _selectedTab = 0;
  int _calibrationSeconds = 5;
  
  String _enrollName = "";
  String _enrollColor = "Red";
  EnrollState _enrollState = EnrollState.idle;
  String? _targetUid;
  int _lockCountdown = 5;
  Timer? _lockTimer;
  StreamSubscription<GloveTelemetry>? _telemetrySub;
  late TextEditingController _hostController;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: 'rehab-glove.local');
    _consoleLogs.add('[System] Dashboard Ready.');
    
    // Load local cube registry
    CubeRegistry.load().then((_) {
      if (mounted) {
        setState(() {
          _consoleLogs.add('[System] Loaded ${CubeRegistry.registry.length} enrolled tags.');
        });
      }
    });
  }

  @override
  void dispose() {
    _cleanupService();
    _consoleScrollController.dispose();
    _hostController.dispose();
    _cancelLockTimer();
    super.dispose();
  }

  void _cleanupService() {
    _telemetrySub?.cancel();
    _telemetrySub = null;
    if (_telemetryService != null) {
      _telemetryService!.disconnect();
      _telemetryService = null;
    }
    _isConnected = false;
  }

  void _toggleConnection() async {
    if (_isConnected) {
      setState(() {
        _cleanupService();
        _consoleLogs.add('[System] Disconnected from Glove.');
      });
      return;
    }

    try {
      _cleanupService();
      
      final service = TelemetryProvider.getService();
      if (service is DirectTelemetryService) {
        service.setHost(_hostController.text);
      }
      _telemetryService = service;

      _consoleLogs.add('[System] Connecting to Glove at ${_hostController.text}...');
      
      // Listen to service logs
      _telemetryService!.logStream.listen((log) {
        if (mounted) {
          setState(() {
            _consoleLogs.add(log);
            if (_consoleLogs.length > 200) _consoleLogs.removeAt(0);
          });
          _scrollConsoleToBottom();
        }
      });

      await _telemetryService!.connect();
      
      _telemetrySub?.cancel();
      _telemetrySub = _telemetryService!.telemetryStream.listen((telemetry) {
        _onTelemetryReceived(telemetry);
      });

      setState(() {
        _isConnected = true;
        _consoleLogs.add('[System] Connection established. Polling active stream...');
      });
    } catch (e) {
      setState(() {
        _consoleLogs.add('[Error] Connection failed: $e');
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      _cleanupService();
    }
  }

  void _cancelLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = null;
  }

  void _onTelemetryReceived(GloveTelemetry telemetry) {
    if (_enrollState == EnrollState.idle || _enrollState == EnrollState.confirmed) {
      return;
    }
    
    // Find active boxes with a placed cube
    final activeCubes = telemetry.boxes
        .map((b) => b['cube'] ?? '')
        .where((c) => c.isNotEmpty)
        .toList();
        
    if (activeCubes.length != 1) {
      // If zero or multiple cubes are detected, reset/go to waiting
      if (_enrollState == EnrollState.locking) {
        setState(() {
          _enrollState = EnrollState.waiting;
          _targetUid = null;
          _lockCountdown = 5;
          _cancelLockTimer();
        });
      }
      return;
    }
    
    final currentUid = activeCubes.first;
    
    if (_enrollState == EnrollState.waiting) {
      // Found exactly one cube! Transition to locking
      setState(() {
        _enrollState = EnrollState.locking;
        _targetUid = currentUid;
        _lockCountdown = 5;
      });
      _startLockTimer();
    } else if (_enrollState == EnrollState.locking) {
      // If the cube UID changed, reset
      if (currentUid != _targetUid) {
        setState(() {
          _enrollState = EnrollState.waiting;
          _targetUid = null;
          _lockCountdown = 5;
          _cancelLockTimer();
        });
      }
    }
  }

  void _startLockTimer() {
    _cancelLockTimer();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_enrollState != EnrollState.locking) {
        timer.cancel();
        return;
      }
      
      if (_lockCountdown > 1) {
        setState(() {
          _lockCountdown--;
        });
      } else {
        timer.cancel();
        // Enrollment confirmed!
        final uid = _targetUid!;
        await CubeRegistry.enrollCube(uid, _enrollName, _enrollColor);
        if (!mounted) return;
        setState(() {
          _enrollState = EnrollState.confirmed;
          _lockCountdown = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tag "$_enrollName" enrolled successfully!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        // Reset form fields
        _enrollName = "";
      }
    });
  }

  void _startEnrollment() {
    if (_enrollName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for the tag')),
      );
      return;
    }
    setState(() {
      _enrollState = EnrollState.waiting;
      _targetUid = null;
      _lockCountdown = 5;
      _cancelLockTimer();
    });
  }

  Color _parseColor(String colorHex) {
    if (colorHex.startsWith('#')) {
      final hex = colorHex.substring(1);
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    switch (colorHex.toLowerCase()) {
      case 'red': return Colors.redAccent;
      case 'green': return Colors.greenAccent;
      case 'blue': return Colors.blueAccent;
      case 'amber': return Colors.amberAccent;
      case 'purple': return Colors.purpleAccent;
      case 'cyan': return Colors.cyanAccent;
      case 'orange': return Colors.orangeAccent;
      case 'pink': return Colors.pinkAccent;
      default: return Colors.blueGrey;
    }
  }

  String _getDatabaseUrl() {
    return "Glove Local API: http://${_hostController.text}";
  }

  void _scrollConsoleToBottom() {
    if (_consoleScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_consoleScrollController.hasClients) {
          _consoleScrollController.animateTo(
            _consoleScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                boxShadow: [
                  BoxShadow(
                    color: _isConnected ? const Color(0xFF10B981).withOpacity(0.5) : const Color(0xFFEF4444).withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'REHAB GLOVE HUB',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                fontSize: 18,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF141722),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: const Color(0xFF0D0E15),
            child: Row(
              children: [
                _buildTab(0, Icons.dashboard, "Live"),
                _buildTab(1, Icons.tune, "Config"),
                _buildTab(2, Icons.nfc, "Enrollment"),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildConnectionPanel(),
          Expanded(
            child: _isConnected
                ? StreamBuilder<GloveTelemetry>(
                    stream: _telemetryService!.telemetryStream,
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      if (data == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      return Stack(
                        children: [
                          IndexedStack(
                            index: _selectedTab,
                            children: [
                              _buildLiveDashboardTab(data),
                              _buildCustomizationTab(data),
                              _buildNfcEnrollmentTab(data),
                            ],
                          ),
                          _buildCalibrationOverlay(data),
                        ],
                      );
                    },
                  )
                : _buildLiveDashboardTab(GloveTelemetry.uncalibrated()),
          ),
          _buildConsoleTerminal(),
        ],
      ),
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFF8B5CF6) : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalibrationOverlay(GloveTelemetry data) {
    if (!data.calibrating) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.accessibility_new, size: 80, color: Color(0xFF8B5CF6)),
              const SizedBox(height: 24),
              const Text(
                'CALIBRATING GLOVE SENSORS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Fully FLEX and EXTEND all fingers, and SQUEEZE the force sensor.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: CircularProgressIndicator(
                      value: data.timeRemaining > 0 ? 1.0 : 0.0,
                      strokeWidth: 10,
                      backgroundColor: const Color(0xFF232A3D),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                    ),
                  ),
                  Text(
                    '${data.timeRemaining}s',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(bottom: BorderSide(color: Color(0xFF232A3D), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.settings_ethernet, size: 16, color: Color(0xFF8B5CF6)),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected ? 'Connected to Glove' : 'Disconnected',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _getDatabaseUrl(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _toggleConnection,
            icon: Icon(_isConnected ? Icons.link_off : Icons.link),
            label: Text(_isConnected ? 'DISCONNECT' : 'CONNECT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isConnected
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveDashboardTab(GloveTelemetry data) {
    if (!_isConnected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'System Offline',
              style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Click CONNECT to start polling the Glove sensor stream.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return _buildTelemetryGrid(data);
  }

  Widget _buildCustomizationTab(GloveTelemetry data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.settings_ethernet, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 10),
                      Text(
                        'GLOVE HOST CONFIGURATION',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Set the hostname or IP address of the rehab glove on your local network.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hostController,
                          decoration: InputDecoration(
                            labelText: 'Glove Host IP / Domain',
                            hintText: 'e.g. rehab-glove.local or 192.168.4.1',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Color(0xFF232A3D)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0D0E15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          final service = TelemetryProvider.getService();
                          if (service is DirectTelemetryService) {
                            service.setHost(_hostController.text);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Host IP updated to: ${_hostController.text}'),
                                backgroundColor: const Color(0xFF8B5CF6),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('UPDATE HOST'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune, color: Color(0xFF10B981)),
                      SizedBox(width: 10),
                      Text(
                        'SENSOR CALIBRATION CONFIG',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Configure dynamic calibration time and trigger remote sensor calibration on the Glove.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Calibration Duration:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$_calibrationSeconds seconds',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _calibrationSeconds.toDouble(),
                    min: 2,
                    max: 15,
                    divisions: 13,
                    activeColor: const Color(0xFF10B981),
                    inactiveColor: const Color(0xFF232A3D),
                    onChanged: (val) {
                      setState(() {
                        _calibrationSeconds = val.toInt();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isConnected
                        ? () async {
                            final service = TelemetryProvider.getService();
                            if (service is DirectTelemetryService) {
                              final success = await service.sendCommand('calibrate', _calibrationSeconds);
                              if (!mounted) return;
                              if (!success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to trigger calibration. Is Glove connected?'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          }
                        : null,
                    icon: const Icon(Icons.flash_on),
                    label: const Text('TRIGGER REMOTE CALIBRATION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF232A3D),
                      disabledForegroundColor: Colors.grey,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNfcEnrollmentTab(GloveTelemetry data) {
    final enrolledCubes = CubeRegistry.registry.values.toList();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.nfc, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 10),
                      Text(
                        'ENROLL NEW NFC TAG',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Input a custom display name, select a color badge, and place a single NFC tag on a smart box to map it.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  
                  if (_enrollState == EnrollState.idle) ...[
                    TextField(
                      onChanged: (val) {
                        _enrollName = val;
                      },
                      decoration: InputDecoration(
                        labelText: 'Tag Name',
                        hintText: 'e.g. Heavy Cube, Blue Cylinder',
                        labelStyle: const TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF232A3D)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0D0E15),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Badge Color: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0E15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF232A3D)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _enrollColor,
                                dropdownColor: const Color(0xFF141722),
                                items: ['Red', 'Green', 'Blue', 'Amber', 'Purple', 'Cyan', 'Orange', 'Pink']
                                    .map((color) => DropdownMenuItem(
                                          value: color,
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: _parseColor(color),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(color),
                                            ],
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _enrollColor = val;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isConnected ? _startEnrollment : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF232A3D),
                        disabledForegroundColor: Colors.grey,
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('START ENROLLMENT FLOW'),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0E15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _enrollState == EnrollState.locking
                              ? _parseColor(_enrollColor)
                              : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_enrollState == EnrollState.waiting) ...[
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Awaiting Tag Placement...',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amberAccent),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Place exactly ONE NFC tag on any smart box to lock onto it.',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ] else if (_enrollState == EnrollState.locking) ...[
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: CircularProgressIndicator(
                                    value: _lockCountdown / 5.0,
                                    strokeWidth: 6,
                                    valueColor: AlwaysStoppedAnimation<Color>(_parseColor(_enrollColor)),
                                    backgroundColor: const Color(0xFF232A3D),
                                  ),
                                ),
                                Text(
                                  '${_lockCountdown}s',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Locking onto Tag: $_targetUid',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Do not remove the tag from the box!',
                              style: TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ] else if (_enrollState == EnrollState.confirmed) ...[
                            const Icon(Icons.check_circle, size: 64, color: Color(0xFF10B981)),
                            const SizedBox(height: 16),
                            const Text(
                              'Tag Enrolled Successfully!',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10B981)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Successfully mapped UID $_targetUid to $_enrollColor.',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 24),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _enrollState = EnrollState.idle;
                                _targetUid = null;
                                _cancelLockTimer();
                              });
                            },
                            child: Text(
                              _enrollState == EnrollState.confirmed ? 'ENROLL ANOTHER' : 'CANCEL ENROLLMENT',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CURRENTLY ENROLLED TAG REGISTRY',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (enrolledCubes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          'No custom tags enrolled yet.',
                          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: enrolledCubes.length,
                      separatorBuilder: (context, index) => const Divider(color: Color(0xFF232A3D)),
                      itemBuilder: (context, index) {
                        final cube = enrolledCubes[index];
                        final badgeColor = _parseColor(cube.colorHex);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: badgeColor.withOpacity(0.2),
                              border: Border.all(color: badgeColor, width: 2),
                            ),
                            child: const Icon(Icons.nfc, size: 16, color: Colors.white),
                          ),
                          title: Text(
                            cube.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'UID: ${cube.uid}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              await CubeRegistry.deleteCube(cube.uid);
                              if (!context.mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Deleted tag "${cube.name}"'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid(GloveTelemetry data) {
    if (!data.calibrated) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1512),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF9E0B).withOpacity(0.3)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 64, color: Color(0xFFFF9E0B)),
              SizedBox(height: 16),
              Text(
                'Awaiting Calibration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF9E0B)),
              ),
              SizedBox(height: 8),
              Text(
                'Please run sensor calibration via the Customization tab, or press the physical button on the Glove.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildGloveSensorsCard(data)),
                    const SizedBox(width: 20),
                    Expanded(child: _buildSmartBoxesCard(data)),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildGloveSensorsCard(data),
                    const SizedBox(height: 20),
                    _buildSmartBoxesCard(data),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGloveSensorsCard(GloveTelemetry data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'GLOVE REHAB SENSORS',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            if (data.flex.percent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No flex sensors detected. Awaiting calibration...',
                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...List.generate(data.flex.percent.length, (index) {
                final val = data.flex.percent[index];
                final rawVal = data.flex.raw.length > index ? data.flex.raw[index] : 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Finger ${index + 1} Flex',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                          ),
                          Text(
                            '$val% (Raw: $rawVal)',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildCustomProgressBar(val / 100.0, const [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                    ],
                  ),
                );
              }),

            const Divider(color: Color(0xFF232A3D), height: 24),

            Builder(
              builder: (context) {
                final val = data.force.percent.isNotEmpty ? data.force.percent.first : 0;
                final rawVal = data.force.raw.isNotEmpty ? data.force.raw.first : 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Force Sensor (FSR)',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                        ),
                        Text(
                          '$val% (Raw: $rawVal)',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildCustomProgressBar(val / 100.0, const [Color(0xFF10B981), Color(0xFF34D399)]),
                  ],
                );
              }
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomProgressBar(double percentage, List<Color> colors) {
    return Container(
      height: 12,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF232A3D)),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: percentage.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.last.withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 1,
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmartBoxesCard(GloveTelemetry data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ACTIVE SMART BOX PLACEMENTS',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (data.boxes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'No active Smart Boxes connected.\nAwaiting registration over ESP-NOW...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  )
                else
                  ...data.boxes.map((box) {
                    final mac = box['mac'] ?? '';
                    final cubeUid = box['cube'] ?? '';
                    final hasCube = cubeUid.isNotEmpty;
                    
                    final enrolled = hasCube ? CubeRegistry.getCube(cubeUid) : null;
                    final badgeColor = enrolled != null ? _parseColor(enrolled.colorHex) : Colors.blueGrey;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0E15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasCube 
                              ? badgeColor.withOpacity(0.4)
                              : const Color(0xFF232A3D),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Box MAC: $mac',
                                style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace'),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hasCube 
                                    ? (enrolled != null ? enrolled.name : 'Unenrolled Tag')
                                    : 'Empty (No Weight)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: hasCube ? Colors.white : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          if (hasCube)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: badgeColor.withOpacity(0.5)),
                              ),
                              child: Text(
                                enrolled != null ? enrolled.colorHex : 'UID: $cubeUid',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: badgeColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            Icon(Icons.crop_free, color: Colors.grey[700]),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WEIGHT MOVEMENT HISTORY (RTDB)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (data.boxActions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'No historical placement actions recorded.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data.boxActions.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final action = data.boxActions[index];
                      final isPlaced = action.isPlaced;
                      final timeString = DateTime.fromMillisecondsSinceEpoch(action.timestamp * 1000)
                          .toLocal()
                          .toString()
                          .split('.')
                          .first;

                      final enrolled = CubeRegistry.getCube(action.cubeId);
                      final badgeColor = enrolled != null ? _parseColor(enrolled.colorHex) : Colors.blueGrey;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0E15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isPlaced ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFFFF9E0B).withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (enrolled != null) ...[
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: badgeColor,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      enrolled != null ? enrolled.name : 'Cube ID: ${action.cubeId}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: enrolled != null ? Colors.white : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Box ${action.boxIndex + 1} | $timeString',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPlaced 
                                    ? const Color(0xFF10B981).withOpacity(0.1)
                                    : const Color(0xFFFF9E0B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isPlaced ? 'Placed' : 'Picked Up',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isPlaced ? const Color(0xFF10B981) : const Color(0xFFFF9E0B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConsoleTerminal() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF06070A),
        border: Border(top: BorderSide(color: Color(0xFF232A3D), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isConsoleExpanded = !_isConsoleExpanded;
              });
              if (_isConsoleExpanded) {
                _scrollConsoleToBottom();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFF10121D),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal, size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      const Text(
                        'Direct Connection Log',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '(${_consoleLogs.length} lines)',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          setState(() {
                            _consoleLogs.clear();
                          });
                        },
                        child: const Text('Clear', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        _isConsoleExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 20,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _isConsoleExpanded ? 150 : 0,
            child: ClipRect(
              child: Container(
                padding: const EdgeInsets.all(12),
                child: ListView.builder(
                  controller: _consoleScrollController,
                  itemCount: _consoleLogs.isEmpty ? 1 : _consoleLogs.length,
                  itemBuilder: (context, index) {
                    if (_consoleLogs.isEmpty) {
                      return const Text(
                        'No logs received.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        _consoleLogs[index],
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
