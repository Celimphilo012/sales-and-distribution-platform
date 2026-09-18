import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` with the real, awaited [SharedPreferences]
/// instance before `runApp`. Left un-overridden, reading it throws —
/// intentionally, since every provider that needs persistence must go
/// through the awaited instance rather than racing a lazy one.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main() before runApp().');
});
