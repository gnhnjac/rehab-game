import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class BoxRegistry {
  static const String _storageKey = 'enrolled_boxes';
  static Map<String, EnrolledBox> _registry = {};
  static StreamSubscription<QuerySnapshot>? _firestoreSub;

  static Map<String, EnrolledBox> get registry => _registry;

  /// Loads locally cached boxes from SharedPreferences, and initiates live sync with Cloud Firestore.
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

    // Connect real-time Firestore sync
    _firestoreSub?.cancel();
    _firestoreSub = FirebaseFirestore.instance.collection('boxes').snapshots().listen((snapshot) {
      _registry = {
        for (var doc in snapshot.docs)
          doc.id: EnrolledBox(
            mac: doc.id,
            name: doc.data()['name'] ?? '',
            shape: doc.data()['shape'] ?? 'circle',
          )
      };
      save(); // Update local SharedPreferences cache
    }, onError: (e) {
      // ignore: avoid_print
      print("Firestore boxes sync error: $e");
    });
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _registry.values.map((b) => b.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(list));
  }

  static Future<void> enrollBox(String mac, String name, String shape) async {
    _registry[mac] = EnrolledBox(mac: mac, name: name, shape: shape);
    await save();

    // Write to Cloud Firestore
    try {
      await FirebaseFirestore.instance.collection('boxes').doc(mac).set({
        'name': name,
        'shape': shape,
      });
    } catch (e) {
      // ignore: avoid_print
      print("Firestore box enroll write failed (saved locally): $e");
    }
  }

  static Future<void> deleteBox(String mac) async {
    _registry.remove(mac);
    await save();

    // Delete from Cloud Firestore
    try {
      await FirebaseFirestore.instance.collection('boxes').doc(mac).delete();
    } catch (e) {
      // ignore: avoid_print
      print("Firestore box delete failed (removed locally): $e");
    }
  }

  static EnrolledBox? getBox(String mac) => _registry[mac];
}
