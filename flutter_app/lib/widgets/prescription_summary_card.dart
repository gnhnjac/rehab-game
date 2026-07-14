// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/game_prescription.dart';

String gameTypeLabel(GameType type) {
  switch (type) {
    case GameType.cubesBoxes:
      return 'Cubes & Boxes';
    case GameType.pinch:
      return 'Pinch Grip';
    case GameType.bend:
      return 'Finger Bend';
  }
}

Color gameTypeColor(GameType type) {
  switch (type) {
    case GameType.cubesBoxes:
      return const Color(0xFF3B82F6); // blue
    case GameType.pinch:
      return const Color(0xFFEC4899); // pink
    case GameType.bend:
      return const Color(0xFF10B981); // emerald
  }
}

IconData gameTypeIcon(GameType type) {
  switch (type) {
    case GameType.cubesBoxes:
      return Icons.widgets_rounded;
    case GameType.pinch:
      return Icons.front_hand_rounded;
    case GameType.bend:
      return Icons.accessibility_new_rounded;
  }
}

String prescriptionSummary(GamePrescription prescription) {
  switch (prescription) {
    case CubesBoxesPrescription p:
      return 'Cycles: ${p.cycles} · Timer: ${p.timerSeconds}s · Target weight: ${p.targetWeightGrams.toStringAsFixed(0)}g';
    case PinchPrescription p:
      return 'Cycles: ${p.cycles} · Hold: ${p.holdDurationSeconds}s · Weight: ${p.targetWeightGrams.toStringAsFixed(0)}g';
    case BendPrescription p:
      return 'Cycles: ${p.cycles} · Hold: ${p.holdDurationSeconds}s · Target ROM: ${p.targetRomPercent.toStringAsFixed(0)}%';
  }
}

class PrescriptionSummaryCard extends StatelessWidget {
  final GamePrescription prescription;
  final VoidCallback onEdit;
  final VoidCallback? onStart;

  const PrescriptionSummaryCard({
    super.key,
    required this.prescription,
    required this.onEdit,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final color = gameTypeColor(prescription.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35), width: 1),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(gameTypeIcon(prescription.type), color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gameTypeLabel(prescription.type),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        prescriptionSummary(prescription),
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                if (onStart != null)
                  IconButton(
                    onPressed: onStart,
                    tooltip: 'Start exercise',
                    icon: Icon(Icons.play_circle_fill_rounded, color: color, size: 30),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
