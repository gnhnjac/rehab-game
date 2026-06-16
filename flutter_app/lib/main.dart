// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/telemetry_provider.dart';
import 'services/telemetry_service.dart';
import 'models/glove_telemetry.dart';

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
    return MaterialApp(
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
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TelemetryService? _telemetryService;
  bool _isConnected = false;

  final List<String> _consoleLogs = [];
  final ScrollController _consoleScrollController = ScrollController();
  bool _isConsoleExpanded = true;

  @override
  void initState() {
    super.initState();
    _consoleLogs.add('[System] Dashboard Ready.');
    if (Firebase.apps.isEmpty) {
      _consoleLogs.add('[Setup Instruction] Please configure `assets/firebase_config.json` with your Firebase credentials to enable live streaming.');
    }
  }

  @override
  void dispose() {
    _cleanupService();
    _consoleScrollController.dispose();
    super.dispose();
  }

  void _cleanupService() {
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
        _consoleLogs.add('[System] Disconnected from Firebase.');
      });
      return;
    }

    if (Firebase.apps.isEmpty) {
      setState(() {
        _consoleLogs.add('[Error] Firebase is not initialized. Please ensure `assets/firebase_config.json` exists with valid credentials.');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firebase configuration missing! See terminal log below.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      _cleanupService();
      _telemetryService = TelemetryProvider.getService();

      final dbUrl = Firebase.app().options.databaseURL ?? 'Default Database';
      _consoleLogs.add('[System] Connecting to Firebase RTDB at $dbUrl...');
      
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
      
      setState(() {
        _isConnected = true;
        _consoleLogs.add('[System] Connection established. Listening to real-time events...');
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

  String _getDatabaseUrl() {
    if (Firebase.apps.isNotEmpty) {
      return Firebase.app().options.databaseURL ?? "No Database URL Specified";
    }
    return "Configuration required in assets/firebase_config.json";
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
      ),
      body: Column(
        children: [
          // Connection Status Panel
          _buildConnectionPanel(),

          // Main Content Grid
          Expanded(
            child: _isConnected
                ? StreamBuilder<GloveTelemetry>(
                    stream: _telemetryService!.telemetryStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Stream Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Waiting for Firebase broadcast...'),
                            ],
                          ),
                        );
                      }

                      final data = snapshot.data!;
                      return _buildTelemetryGrid(data);
                    },
                  )
                : const Center(
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
                          'Click CONNECT to subscribe to the Firebase Realtime Database stream.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
          ),

          // Debug Console Terminal
          _buildConsoleTerminal(),
        ],
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
                    const Icon(Icons.cloud, size: 16, color: Color(0xFF8B5CF6)),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected ? 'Connected to Firebase RTDB' : 'Disconnected',
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
            icon: Icon(_isConnected ? Icons.cloud_off : Icons.cloud_queue),
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
                'Please press the Calibration Button (GPIO 4) on the Glove board and extend/flex all fingers.',
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
                // Wide layout: side-by-side
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildGloveSensorsCard(data)),
                    const SizedBox(width: 20),
                    Expanded(child: _buildSmartBoxesCard(data)),
                  ],
                );
              } else {
                // Narrow layout: stacked
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

            // Flex Sensors Bars
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

            // Force FSR Sensor
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'WEIGHT MOVEMENT TRACKING',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            if (data.boxActions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No weights registered.\nAwaiting connection over ESP-NOW...',
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
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final action = data.boxActions[index];
                  final isPlaced = action.isPlaced;
                  final timeString = DateTime.fromMillisecondsSinceEpoch(action.timestamp * 1000)
                      .toLocal()
                      .toString()
                      .split('.')
                      .first;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0E15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPlaced ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFFF9E0B).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Weight ID: ${action.cubeId}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPlaced 
                                    ? const Color(0xFF10B981).withOpacity(0.1)
                                    : const Color(0xFFFF9E0B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle, 
                                    size: 8, 
                                    color: isPlaced ? const Color(0xFF10B981) : const Color(0xFFFF9E0B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isPlaced ? 'Placed (הונח)' : 'Picked Up (הורם)',
                                    style: TextStyle(
                                      fontSize: 11, 
                                      color: isPlaced ? const Color(0xFF10B981) : const Color(0xFFFF9E0B), 
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141722),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Box Index:',
                                    style: TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                  Text(
                                    'Box ${action.boxIndex + 1}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF8B5CF6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Last Event Time:',
                                    style: TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                  Text(
                                    timeString,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
          // Console Header Toggle
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
                        'Firebase Terminal Log',
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

          // Console Log Text Body
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
