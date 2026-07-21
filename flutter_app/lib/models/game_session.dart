import 'game_prescription.dart';

/// A single completed game session record (mirrors Dara's Firestore
/// `game_history` document shape). Used to drive the analytics charts.
class GameSession {
  final String id;
  final String patientId;
  final GameType gameType;
  final DateTime timestamp;
  final int successCount;
  final int totalCycles;

  /// Per-session aggregate metrics used by the analytics charts.
  final double avgResponseTimeMs; // reaction/response time
  final double avgGripForceGrams; // grip/pinch force
  final double avgRomPercent; // finger range of motion

  // Per-finger ROM
  final double romThumb;
  final double romIndex;
  final double romMiddle;
  final double romRing;
  final double romPinky;

  const GameSession({
    required this.id,
    required this.patientId,
    required this.gameType,
    required this.timestamp,
    required this.successCount,
    required this.totalCycles,
    required this.avgResponseTimeMs,
    required this.avgGripForceGrams,
    required this.avgRomPercent,
    required this.romThumb,
    required this.romIndex,
    required this.romMiddle,
    required this.romRing,
    required this.romPinky,
  });

  double get successRate => totalCycles == 0 ? 0 : successCount / totalCycles;

  factory GameSession.fromFirestore(String id, Map<String, dynamic> data) {
    final metrics = (data['metrics'] as Map?)?.cast<String, dynamic>() ?? {};
    final ts = data['timestamp'];
    DateTime timestamp;
    if (ts is DateTime) {
      timestamp = ts;
    } else if (ts != null && ts is Comparable) {
      // Firestore Timestamp exposes toDate(); fall back to now if absent.
      try {
        timestamp = (ts as dynamic).toDate() as DateTime;
      } catch (_) {
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }

    GameType parseType(String? raw) {
      switch (raw) {
        case 'pinch':
          return GameType.pinch;
        case 'bend':
          return GameType.bend;
        default:
          return GameType.cubesBoxes;
      }
    }

    return GameSession(
      id: id,
      patientId: (data['patientId'] ?? '') as String,
      gameType: parseType(data['gameType'] as String?),
      timestamp: timestamp,
      successCount: (data['successCount'] ?? 0) as int,
      totalCycles: (data['totalCycles'] ?? 0) as int,
      avgResponseTimeMs: (metrics['avgResponseTimeMs'] as num?)?.toDouble() ?? 0,
      avgGripForceGrams: (metrics['avgGripForceGrams'] as num?)?.toDouble() ?? 0,
      avgRomPercent: (metrics['avgRomPercent'] as num?)?.toDouble() ?? 0,
      romThumb: (metrics['romThumb'] as num?)?.toDouble() ?? 0,
      romIndex: (metrics['romIndex'] as num?)?.toDouble() ?? 0,
      romMiddle: (metrics['romMiddle'] as num?)?.toDouble() ?? 0,
      romRing: (metrics['romRing'] as num?)?.toDouble() ?? 0,
      romPinky: (metrics['romPinky'] as num?)?.toDouble() ?? 0,
    );
  }
}
