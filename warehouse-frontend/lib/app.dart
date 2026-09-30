import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell/branding.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'routing/app_router.dart';
import 'shared/nx/nx_overlays.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    // The accent palette and fonts follow the company's brand (Settings → Branding).
    final brand = ref.watch(brandColorProvider);
    final fonts = ref.watch(brandFontsProvider);

    return MaterialApp.router(
      // The tab title follows the company name (Settings → Branding).
      title: ref.watch(brandTitleProvider),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(brand: brand, headingFont: fonts.heading, bodyFont: fonts.body),
      darkTheme: AppTheme.dark(brand: brand, headingFont: fonts.heading, bodyFont: fonts.body),
      themeMode: themeMode,
      routerConfig: router,
      // Toasts float above every route, sheet and dialog; the favicon follows the company logo.
      builder: (context, child) => NxToastHost(child: BrandingEffects(child: child ?? const SizedBox.shrink())),
    );
  }
}
