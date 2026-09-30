import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/brand_palette.dart';
import '../core/theme/nocturne.dart';
import '../features/settings/data/branding_api.dart';
import '../shared/browser_branding.dart';

/// The product name shown when no company name has been set.
const kDefaultBrandName = 'Warehouse System';

/// The company name from Settings → Branding (public — also known on the
/// sign-in page), or [kDefaultBrandName] while loading / when unset.
final brandNameProvider = Provider<String>((ref) {
  final name = ref.watch(brandingProvider).value?.companyName.trim();
  return (name == null || name.isEmpty) ? kDefaultBrandName : name;
});

/// The brand colour (Settings → Branding) the whole console's accent is
/// generated from, or null for the built-in violet.
final brandColorProvider = Provider<Color?>((ref) => BrandPalette.parse(ref.watch(brandingProvider).value?.brandColor));

/// The approved brand fonts (heading, body); nulls keep Inter.
final brandFontsProvider = Provider<({String? heading, String? body})>((ref) {
  final b = ref.watch(brandingProvider).value;
  return (heading: b?.headingFont, body: b?.bodyFont);
});

/// The tagline under the company name, or null.
final brandTaglineProvider = Provider<String?>((ref) {
  final t = ref.watch(brandingProvider).value?.tagline?.trim();
  return (t == null || t.isEmpty) ? null : t;
});

/// The uploaded company logo, or null (the built-in mark is drawn instead).
final brandLogoProvider = Provider<Uint8List?>((ref) => ref.watch(brandingLogoProvider).value);

/// The browser tab title: "Acme Distribution · Warehouse", or just the
/// product name when no company name is set.
final brandTitleProvider = Provider<String>((ref) {
  final name = ref.watch(brandNameProvider);
  return name == kDefaultBrandName ? kDefaultBrandName : '$name · Warehouse';
});

/// Keeps the browser tab's icon (the company logo) and the mobile browser's
/// toolbar colour (the brand colour) in step with Settings → Branding — set
/// once the branding loads, and again whenever an administrator changes it.
class BrandingEffects extends ConsumerStatefulWidget {
  const BrandingEffects({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BrandingEffects> createState() => _BrandingEffectsState();
}

class _BrandingEffectsState extends ConsumerState<BrandingEffects> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<Uint8List?>(brandLogoProvider, (_, logo) => applyBrowserFavicon(logo), fireImmediately: true);
    ref.listenManual<Color?>(brandColorProvider, (_, c) => applyBrowserThemeColor(c == null ? null : BrandPalette.hex(c)), fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The brand square: the uploaded company logo when there is one, otherwise
/// the built-in accent-outlined warehouse mark.
class BrandMark extends ConsumerWidget {
  const BrandMark({super.key, this.size = 26, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = ref.watch(brandLogoProvider);
    if (logo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.27),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.memory(logo, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => _DefaultMark(size: size, glow: glow)),
        ),
      );
    }
    return _DefaultMark(size: size, glow: glow);
  }
}

class _DefaultMark extends StatelessWidget {
  const _DefaultMark({required this.size, required this.glow});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: n.accent),
        boxShadow: glow ? [BoxShadow(color: n.accent.withValues(alpha: 0.35), blurRadius: 14)] : null,
      ),
      alignment: Alignment.center,
      child: Icon(PhosphorIconsBold.warehouse, size: size * 0.54, color: n.accent),
    );
  }
}
