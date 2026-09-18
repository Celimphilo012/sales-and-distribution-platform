import 'package:flutter/material.dart';

import '../shared/widgets/empty_loading_error_states.dart';

/// Shown only while the initial session restore (`AuthNotifier.build()`) is
/// in flight — reading tokens from secure storage and, if present,
/// validating them against the backend. Prevents a flash of the login
/// screen on every page reload.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingStateView());
  }
}
