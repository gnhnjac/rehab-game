import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/game_prescription.dart';
import '../models/game_session.dart';

abstract class GameHistoryRepository {
  Future<List<GameSession>> getSessionsForPatient(String patientId);
}

class FirestoreGameHistoryRepository implements GameHistoryRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Future<List<GameSession>> getSessionsForPatient(String patientId) async {
    try {
      final snapshot = await _db
          .collection('game_history')
          .where('patientId', isEqualTo: patientId)
          .get();

      final list = snapshot.docs
          .map((doc) => GameSession.fromFirestore(doc.id, doc.data()))
          .toList();
      
      // Sort in-memory in descending order of timestamp to avoid requiring a composite index
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      return [];
    }
  }
}

/// In-memory history with a plausible upward-trending recovery curve, so the
/// analytics charts render without a live Firestore backend.
class MockGameHistoryRepository implements GameHistoryRepository {
  @override
  Future<List<GameSession>> getSessionsForPatient(String patientId) async {
    final rng = Random(patientId.hashCode);
    final now = DateTime.now();
    final sessions = <GameSession>[];

    const sessionCount = 12;
    for (var i = 0; i < sessionCount; i++) {
      // progress goes 0 -> 1 across the sessions (recovery over time)
      final progress = i / (sessionCount - 1);
      final date = now.subtract(Duration(days: (sessionCount - 1 - i) * 3));
      final gameType = GameType.values[i % GameType.values.length];

      final totalCycles = 10;
      // Success improves over time with a little noise.
      final successRate = (0.4 + 0.5 * progress + (rng.nextDouble() - 0.5) * 0.15).clamp(0.0, 1.0);
      final successCount = (successRate * totalCycles).round();

      // Response time drops (improves) over time.
      final responseTime = 1400 - 700 * progress + (rng.nextDouble() - 0.5) * 120;
      // Grip force rises over time.
      final gripForce = 200 + 300 * progress + (rng.nextDouble() - 0.5) * 40;
      // ROM rises over time.
      final rom = 45 + 45 * progress + (rng.nextDouble() - 0.5) * 8;

      sessions.add(GameSession(
        id: '${patientId}_s$i',
        patientId: patientId,
        gameType: gameType,
        timestamp: date,
        successCount: successCount,
        totalCycles: totalCycles,
        avgResponseTimeMs: responseTime,
        avgGripForceGrams: gripForce,
        avgRomPercent: rom.clamp(0, 100),
      ));
    }
    return sessions;
  }
}

class GameHistoryRepositoryProvider {
  static GameHistoryRepository? _instance;

  static GameHistoryRepository getRepository() {
    return _instance ??= FirestoreGameHistoryRepository();
  }
}
