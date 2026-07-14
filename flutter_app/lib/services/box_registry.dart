import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A smart box mapped to a human-friendly identity.
class EnrolledBox {
  final String mac;
  final String name;
  final String shape; // e.g. "circle", "square", "triangle", "star"

  EnrolledBox({required this.mac, required this.name, required this.shape});

  Map<String, dynamic> toJson() => {'mac': mac, 'name': name, 'shape': shape};

  factory EnrolledBox.fromJson(Map<String, dynamic> json) => EnrolledBox(
        mac: json['mac'] as String,
        name: json['name'] as String,
        shape: json['shape'] as String,
      );
}

/// Local persistence for smart-box identities (Task I.5), mirroring the
/// existing [CubeRegistry] pattern so it works offline. Keyed by MAC address.
class BoxRegistry {
  static const String _storageKey = 'enrolled_boxes';
  static Map<String, EnrolledBox> _registry = {};

  static Map<String, EnrolledBox> get registry => _registry;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> list = jsonDecode(jsonString);
        _registry = {
          for (var item in list) item['mac'] as String: EnrolledBox.fromJson(item)
        };
      }
    } catch (_) {
      // Ignore corrupt storage; start with an empty registry.
    }
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _registry.values.map((b) => b.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(list));
  }

  static Future<void> enrollBox(String mac, String name, String shape) async {
    _registry[mac] = EnrolledBox(mac: mac, name: name, shape: shape);
    await save();
  }

  static Future<void> deleteBox(String mac) async {
    _registry.remove(mac);
    await save();
  }

  static EnrolledBox? getBox(String mac) => _registry[mac];
}
