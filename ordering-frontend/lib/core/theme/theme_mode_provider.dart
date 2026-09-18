import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistence/shared_preferences_provider.dart';

const _themeModeKey = 'settings.themeMode';

/// Persisted light/dark/system theme choice. Drives `MaterialApp.themeMode`
/// and survives app restarts via [SharedPreferences].
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_themeModeKey);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(_themeModeKey, mode.name);
  }

  Future<void> toggle() async {
    final next = switch (state) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => ThemeMode.light,
    };
    await setThemeMode(next);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
