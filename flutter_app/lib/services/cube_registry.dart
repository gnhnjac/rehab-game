import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnrolledCube {
  final String uid;
  final String name;
  final String colorHex; // Hex color representation or simple name

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
  static StreamSubscription<QuerySnapshot>? _firestoreSub;

  static Map<String, EnrolledCube> get registry => _registry;

  /// Loads locally cached cubes from SharedPreferences, and initiates live sync with Cloud Firestore.
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
      print("Error loading local cube cache: $e");
    }

    // Connect real-time Firestore sync
    _firestoreSub?.cancel();
    _firestoreSub = FirebaseFirestore.instance.collection('cubes').snapshots().listen((snapshot) {
      _registry = {
        for (var doc in snapshot.docs)
          doc.id: EnrolledCube(
            uid: doc.id,
            name: doc.data()['name'] ?? '',
            colorHex: doc.data()['color'] ?? doc.data()['colorHex'] ?? 'Red',
          )
      };
      save(); // Update local SharedPreferences cache
    }, onError: (e) {
      // ignore: avoid_print
      print("Firestore cubes sync error: $e");
    });
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

    // Write to Cloud Firestore
    try {
      await FirebaseFirestore.instance.collection('cubes').doc(uid).set({
        'name': name,
        'color': colorHex,
        'shape': 'circle', // default shape mapping
        'weightGrams': 100, // default weight mapping
      });
    } catch (e) {
      // ignore: avoid_print
      print("Firestore cube enroll write failed (saved locally): $e");
    }
  }

  static Future<void> deleteCube(String uid) async {
    _registry.remove(uid);
    await save();

    // Delete from Cloud Firestore
    try {
      await FirebaseFirestore.instance.collection('cubes').doc(uid).delete();
    } catch (e) {
      // ignore: avoid_print
      print("Firestore cube delete failed (removed locally): $e");
    }
  }

  static EnrolledCube? getCube(String uid) {
    return _registry[uid];
  }
}
