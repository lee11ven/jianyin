import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent local random device id (not an account).
class DeviceIdStore {
  static const _prefsKey = 'signspeak.deviceId.v1';

  String? _cached;

  Future<String> getOrCreate() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }
    final id = _generate();
    await prefs.setString(_prefsKey, id);
    _cached = id;
    return id;
  }

  static String _generate() {
    final r = Random.secure();
    final bytes = List<int>.generate(8, (_) => r.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'app-$hex';
  }
}
