import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'services/telemetry_provider.dart';
import 'services/telemetry_service.dart';
import 'models/glove_telemetry.dart';

void main() {
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
  TelemetrySource _activeSource = TelemetrySource.serial;
  String? _selectedPort;
  List<String> _availablePorts = [];
  TelemetryService? _telemetryService;

  final List<String> _consoleLogs = [];
  final ScrollController _consoleScrollController = ScrollController();
  bool _isConsoleExpanded = false;

  @override
  void initState() {
    super.initState();
    _scanPorts();
  }

  @override
  void dispose() {
    _cleanupService();
    _consoleScrollController.dispose();
    super.dispose();
  }

  void _scanPorts() {
    setState(() {
      _availablePorts = SerialPort.availablePorts;
      if (_availablePorts.isNotEmpty) {
        // Default to first available COM port
        _selectedPort = _availablePorts.contains(_selectedPort)
            ? _selectedPort
            : _availablePorts.first;
      } else {
        _selectedPort = null;
      }
    });
  }

  void _cleanupService() {
    if (_telemetryService != null) {
      _telemetryService!.disconnect();
      _telemetryService = null;
    }
  }

  void _toggleConnection() async {
    if (_telemetryService != null && _telemetryService!.isConnected) {
      setState(() {
        _cleanupService();
        _consoleLogs.add('[System] Disconnected.');
      });
      return;
    }

    if (_activeSource == TelemetrySource.serial && _selectedPort == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a COM port first.')),
      );
      return;
    }

    try {
      _cleanupService();
      
      _telemetryService = TelemetryProvider.getService(
        _activeSource,
        serialPort: _selectedPort ?? 'COM3',
      );

      _consoleLogs.add('[System] Connecting to ${_activeSource == TelemetrySource.serial ? _selectedPort : "Firebase"}...');

      // Listen to raw text logs
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
        _consoleLogs.add('[System] Connection established.');
      });
    } catch (e) {
      setState(() {
        _consoleLogs.add('[Error] Connection failed: $e');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
      _cleanupService();
    }
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
    final bool isConnected = _telemetryService != null && _telemetryService!.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                boxShadow: [
                  BoxShadow(
                    color: isConnected ? const Color(0xFF10B981).withOpacity(0.5) : const Color(0xFFEF4444).withOpacity(0.5),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            tooltip: 'Rescan Serial Ports',
            onPressed: isConnected ? null : _scanPorts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Control Panel
          _buildConnectionPanel(isConnected),

          // Main Telemetry Body
          Expanded(
            child: isConnected
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
                              Text('Waiting for Glove data broadcast...'),
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
                        Icon(Icons.usb_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'System Offline',
                          style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Select your Glove source and click Connect.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
          ),

          // Collapsible Console Terminal
          _buildConsoleTerminal(),
        ],
      ),
    );
  }

  Widget _buildConnectionPanel(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(bottom: BorderSide(color: Color(0xFF232A3D), width: 1)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Source Switcher Toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Source:  ', style: TextStyle(fontWeight: FontWeight.w600)),
              SegmentedButton<TelemetrySource>(
                segments: const [
                  ButtonSegment<TelemetrySource>(
                    value: TelemetrySource.serial,
                    label: Text('USB Serial'),
                    icon: Icon(Icons.usb),
                  ),
                  ButtonSegment<TelemetrySource>(
                    value: TelemetrySource.firebase,
                    label: Text('Firebase'),
                    icon: Icon(Icons.cloud),
                  ),
                ],
                selected: {_activeSource},
                onSelectionChanged: isConnected
                    ? null
                    : (Set<TelemetrySource> selection) {
                        setState(() {
                          _activeSource = selection.first;
                        });
                      },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),

          // COM Port Selection (Visible only when Serial is selected)
          if (_activeSource == TelemetrySource.serial)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Port:  ', style: TextStyle(fontWeight: FontWeight.w600)),
                _availablePorts.isEmpty
                    ? const Text(
                        'No ports detected',
                        style: TextStyle(color: Colors.redAccent, fontStyle: FontStyle.italic),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0E15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF232A3D)),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedPort,
                          underline: const SizedBox(),
                          disabledHint: Text(_selectedPort ?? 'None'),
                          dropdownColor: const Color(0xFF141722),
                          onChanged: isConnected
                              ? null
                              : (String? newValue) {
                                  setState(() {
                                    _selectedPort = newValue;
                                  });
                                },
                          items: _availablePorts.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                        ),
                      ),
              ],
            ),

          // Connect / Disconnect Action Button
          ElevatedButton.icon(
            onPressed: _toggleConnection,
            icon: Icon(isConnected ? Icons.link_off : Icons.link),
            label: Text(isConnected ? 'DISCONNECT' : 'CONNECT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected
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
            ...List.generate(data.flex.length, (index) {
              final val = data.flex[index];
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
                          '$val%',
                          style: const TextStyle(
                            fontFamily: 'Courier',
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
            Column(
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
                      '${data.force}%',
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCustomProgressBar(data.force / 100.0, const [Color(0xFF10B981), Color(0xFF34D399)]),
              ],
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
              'SMART BOX TELEMETRY',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            if (data.boxes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No boxes registered.\nAwaiting connection over ESP-NOW...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: data.boxes.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final box = data.boxes[index];
                  final hasCube = box.isCubePresent;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0E15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasCube ? const Color(0xFF8B5CF6).withOpacity(0.3) : const Color(0xFF232A3D),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Box MAC: ${box.mac}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Online',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'NFC Cube Slot:',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                              Text(
                                hasCube ? box.cubeUid : '[EMPTY]',
                                style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: hasCube ? const Color(0xFF8B5CF6) : Colors.grey,
                                  shadows: hasCube
                                      ? [Shadow(color: const Color(0xFF8B5CF6).withOpacity(0.5), blurRadius: 8)]
                                      : null,
                                ),
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
                        'Raw Console Debug Terminal Log',
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
                        'No console logs received. Connect to a source to begin.',
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
