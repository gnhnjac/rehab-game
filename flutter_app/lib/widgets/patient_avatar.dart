import 'package:flutter/material.dart';

const List<Color> _avatarPalette = [
  Color(0xFF8B5CF6), // purple
  Color(0xFF10B981), // emerald
  Color(0xFF3B82F6), // blue
  Color(0xFFEC4899), // pink
  Color(0xFFF59E0B), // amber
  Color(0xFF14B8A6), // teal
];

Color colorForPatientId(String id) {
  final hash = id.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return _avatarPalette[hash % _avatarPalette.length];
}

String initialsForName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

class PatientAvatar extends StatelessWidget {
  final String id;
  final String name;
  final double radius;

  const PatientAvatar({
    super.key,
    required this.id,
    required this.name,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorForPatientId(id);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initialsForName(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
