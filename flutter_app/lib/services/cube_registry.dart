import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EnrolledCube {
  final String uid;
  final String name;
  final String colorHex; // Hex color representation (e.g. "#FF0000" or simple name)

  EnrolledCube({
    required this.uid,
    required this.name,
    required this.colorHex,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'colorHex': colorHex,
      };

  factory EnrolledCube.fromJson(Map<String, dynamic> json) {
    return EnrolledCube(
      uid: json['uid'] as String,
      name: json['name'] as String,
      colorHex: json['colorHex'] as String,
    );
  }
}

class CubeRegistry {
  static const String _storageKey = 'enrolled_cubes';
  static Map<String, EnrolledCube> _registry = {};

  static Map<String, EnrolledCube> get registry => _registry;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> list = jsonDecode(jsonString);
        _registry = {
          for (var item in list)
            item['uid'] as String: EnrolledCube.fromJson(item)
        };
      }
    } catch (e) {
      // ignore: avoid_print
      print("Error loading cube registry: $e");
    }
  }

  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _registry.values.map((c) => c.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(list));
    } catch (e) {
      // ignore: avoid_print
      print("Error saving cube registry: $e");
    }
  }

  static Future<void> enrollCube(String uid, String name, String colorHex) async {
    _registry[uid] = EnrolledCube(uid: uid, name: name, colorHex: colorHex);
    await save();
  }

  static Future<void> deleteCube(String uid) async {
    _registry.remove(uid);
    await save();
  }

  static EnrolledCube? getCube(String uid) {
    return _registry[uid];
  }
}
