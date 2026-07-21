// ignore_for_file: deprecated_member_use
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/game_session.dart';
import '../repositories/game_history_repository.dart';

/// Task I.3 — Analytics & Reporting.
///
/// Progress charts over time for one patient: success rate, response time,
/// grip force and finger ROM. Data comes from a [GameHistoryRepository]
/// (currently a mock; swappable to Dara's Firestore game_history stream).
class AnalyticsScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const AnalyticsScreen({super.key, required this.patientId, required this.patientName});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<List<GameSession>> _future;
  String _selectedFinger = 'Average';

  @override
  void initState() {
    super.initState();
    _future = GameHistoryRepositoryProvider.getRepository()
        .getSessionsForPatient(widget.patientId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Progress · ${widget.patientName}')),
      body: FutureBuilder<List<GameSession>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = [...snapshot.data!]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          if (sessions.isEmpty) {
            return const Center(
              child: Text('No sessions recorded yet.', style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummary(sessions),
              const SizedBox(height: 20),
              _buildChartCard(
                'Success rate',
                'Share of cycles completed successfully',
                const Color(0xFF10B981),
                sessions,
                (s) => s.successRate * 100,
                unit: '%',
                minY: 0,
                maxY: 100,
              ),
              _buildChartCard(
                'Response time',
                'Average reaction time per cycle',
                const Color(0xFF3B82F6),
                sessions,
                (s) => s.avgResponseTimeMs,
                unit: 'ms',
              ),
              _buildChartCard(
                'Grip force',
                'Average grip / pinch force',
                const Color(0xFFEC4899),
                sessions,
                (s) => s.avgGripForceGrams,
                unit: 'g',
              ),
              _buildFlexRomChartCard(sessions),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummary(List<GameSession> sessions) {
    final latest = sessions.last;
    final first = sessions.first;
    final successDelta = (latest.successRate - first.successRate) * 100;
    return Row(
      children: [
        _buildStatTile('Sessions', '${sessions.length}', Icons.event_note, const Color(0xFF8B5CF6)),
        const SizedBox(width: 10),
        _buildStatTile('Latest success', '${(latest.successRate * 100).round()}%', Icons.check_circle,
            const Color(0xFF10B981)),
        const SizedBox(width: 10),
        _buildStatTile(
          'Improvement',
          '${successDelta >= 0 ? '+' : ''}${successDelta.round()}%',
          successDelta >= 0 ? Icons.trending_up : Icons.trending_down,
          successDelta >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
        ),
      ],
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141722),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF232A3D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(
    String title,
    String subtitle,
    Color color,
    List<GameSession> sessions,
    double Function(GameSession) value, {
    String unit = '',
    double? minY,
    double? maxY,
  }) {
    final spots = <FlSpot>[
      for (var i = 0; i < sessions.length; i++) FlSpot(i.toDouble(), value(sessions[i])),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFF232A3D), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (sessions.length / 4).ceilToDouble().clamp(1, double.infinity),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= sessions.length) return const SizedBox.shrink();
                        final d = sessions[i].timestamp;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${d.month}/${d.day}',
                              style: const TextStyle(color: Colors.grey, fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
                    ),
                    belowBarData: BarAreaData(show: true, color: color.withOpacity(0.12)),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(unit == 'ms' || unit == 'g' ? 0 : 1)}$unit',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlexRomChartCard(List<GameSession> sessions) {
    final color = const Color(0xFFF59E0B);
    final spots = <FlSpot>[
      for (var i = 0; i < sessions.length; i++)
        FlSpot(
          i.toDouble(),
          _getFingerRomValue(sessions[i], _selectedFinger),
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  const Text('Finger ROM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              DropdownButton<String>(
                value: _selectedFinger,
                dropdownColor: const Color(0xFF141722),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                items: ['Average', 'Thumb', 'Index', 'Middle', 'Ring', 'Pinky']
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedFinger = val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text('Range of motion (flex) progress', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFF232A3D), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (sessions.length / 4).ceilToDouble().clamp(1, double.infinity),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= sessions.length) return const SizedBox.shrink();
                        final d = sessions[i].timestamp;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${d.month}/${d.day}',
                              style: const TextStyle(color: Colors.grey, fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
                    ),
                    belowBarData: BarAreaData(show: true, color: color.withOpacity(0.12)),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(1)}%',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _getFingerRomValue(GameSession s, String finger) {
    switch (finger) {
      case 'Thumb':
        return s.romThumb;
      case 'Index':
        return s.romIndex;
      case 'Middle':
        return s.romMiddle;
      case 'Ring':
        return s.romRing;
      case 'Pinky':
        return s.romPinky;
      default:
        return s.avgRomPercent;
    }
  }
}
