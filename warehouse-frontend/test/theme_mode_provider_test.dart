import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_frontend/core/persistence/shared_preferences_provider.dart';
import 'package:warehouse_frontend/core/theme/theme_mode_provider.dart';

Future<ProviderContainer> _container({Map<String, Object> stored = const {}}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('defaults to dark ("nocturne" is home) when nothing is stored yet', () async {
    final container = await _container();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('still respects an explicitly stored light/dark/system choice', () async {
    final light = await _container(stored: {'settings.themeMode': 'light'});
    expect(light.read(themeModeProvider), ThemeMode.light);

    final system = await _container(stored: {'settings.themeMode': 'system'});
    expect(system.read(themeModeProvider), ThemeMode.system);

    final dark = await _container(stored: {'settings.themeMode': 'dark'});
    expect(dark.read(themeModeProvider), ThemeMode.dark);
  });

  test('toggle cycles dark -> light -> dark, and persists the choice', () async {
    final container = await _container();
    final notifier = container.read(themeModeProvider.notifier);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    await notifier.toggle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    await notifier.toggle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('toggle from system goes to light (never silently back to system)', () async {
    final container = await _container(stored: {'settings.themeMode': 'system'});
    final notifier = container.read(themeModeProvider.notifier);

    await notifier.toggle();
    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
