import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    required this.confidence,
    required this.depthSoft,
    required this.depthHard,
    required this.biasSoft,
    required this.biasHard,
    required this.shakeSensitivity,
    required this.tPrimeMs,
  });

  final double confidence;
  final double depthSoft;
  final double depthHard;
  final double biasSoft;
  final double biasHard;
  final double shakeSensitivity;
  final double tPrimeMs;

  static const defaults = AppSettings(
    confidence: 0.65,
    depthSoft: 0.17,
    depthHard: 0.67,
    biasSoft: 0.17,
    biasHard: 0.78,
    shakeSensitivity: 0.5,
    tPrimeMs: 100,
  );

  AppSettings copyWith({
    double? confidence,
    double? depthSoft,
    double? depthHard,
    double? biasSoft,
    double? biasHard,
    double? shakeSensitivity,
    double? tPrimeMs,
  }) {
    return AppSettings(
      confidence: confidence ?? this.confidence,
      depthSoft: depthSoft ?? this.depthSoft,
      depthHard: depthHard ?? this.depthHard,
      biasSoft: biasSoft ?? this.biasSoft,
      biasHard: biasHard ?? this.biasHard,
      shakeSensitivity: shakeSensitivity ?? this.shakeSensitivity,
      tPrimeMs: tPrimeMs ?? this.tPrimeMs,
    );
  }

  String format(String key) {
    switch (key) {
      case 'tPrimeMs':
        return '${tPrimeMs.round()} ms';
      case 'confidence':
        return confidence.toStringAsFixed(2);
      case 'depthSoft':
        return depthSoft.toStringAsFixed(2);
      case 'depthHard':
        return depthHard.toStringAsFixed(2);
      case 'biasSoft':
        return biasSoft.toStringAsFixed(2);
      case 'biasHard':
        return biasHard.toStringAsFixed(2);
      case 'shakeSensitivity':
        return shakeSensitivity.toStringAsFixed(2);
      default:
        return '';
    }
  }
}

/// Persists settings under key aligned with prototype `signspeak.settings.v1`.
class SettingsStore extends ChangeNotifier {
  static const prefsKey = 'signspeak.settings.v1';

  AppSettings _settings = AppSettings.defaults;
  bool loaded = false;

  AppSettings get settings => _settings;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _settings = AppSettings(
      confidence: prefs.getDouble('$prefsKey.confidence') ??
          AppSettings.defaults.confidence,
      depthSoft: prefs.getDouble('$prefsKey.depthSoft') ??
          AppSettings.defaults.depthSoft,
      depthHard: prefs.getDouble('$prefsKey.depthHard') ??
          AppSettings.defaults.depthHard,
      biasSoft:
          prefs.getDouble('$prefsKey.biasSoft') ?? AppSettings.defaults.biasSoft,
      biasHard:
          prefs.getDouble('$prefsKey.biasHard') ?? AppSettings.defaults.biasHard,
      shakeSensitivity: prefs.getDouble('$prefsKey.shakeSensitivity') ??
          AppSettings.defaults.shakeSensitivity,
      tPrimeMs: prefs.getDouble('$prefsKey.tPrimeMs') ??
          AppSettings.defaults.tPrimeMs,
    );
    loaded = true;
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$prefsKey.confidence', next.confidence);
    await prefs.setDouble('$prefsKey.depthSoft', next.depthSoft);
    await prefs.setDouble('$prefsKey.depthHard', next.depthHard);
    await prefs.setDouble('$prefsKey.biasSoft', next.biasSoft);
    await prefs.setDouble('$prefsKey.biasHard', next.biasHard);
    await prefs.setDouble('$prefsKey.shakeSensitivity', next.shakeSensitivity);
    await prefs.setDouble('$prefsKey.tPrimeMs', next.tPrimeMs);
  }

  Future<void> reset() => update(AppSettings.defaults);
}
