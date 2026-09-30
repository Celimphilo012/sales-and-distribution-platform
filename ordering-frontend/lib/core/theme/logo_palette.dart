import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The logo's main colours, most prominent first — suggested brand colours
/// (Settings → Branding → Colour).
///
/// The logo is decoded small (64 px wide) and every clearly coloured pixel
/// (not transparent, not near-white / near-black / grey) is sorted into one
/// of 36 hue buckets, weighted by how vivid it is. The heaviest buckets, at
/// least 24° apart, give the palette (each the average colour of its bucket).
Future<List<Color>> logoPalette(Uint8List bytes, {int max = 5}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) return const [];

  final weight = List<double>.filled(36, 0);
  final sum = List.generate(36, (_) => [0.0, 0.0, 0.0, 0.0]);
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final a = data.getUint8(i + 3);
    if (a < 160) continue;
    final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < 0.2 || hsl.lightness < 0.12 || hsl.lightness > 0.92) continue;
    final bin = (hsl.hue / 10).floor() % 36;
    final w = hsl.saturation;
    weight[bin] += w;
    final s = sum[bin];
    s[0] += (c.r * 255) * w;
    s[1] += (c.g * 255) * w;
    s[2] += (c.b * 255) * w;
    s[3] += w;
  }

  final order = List.generate(36, (i) => i)..sort((a, b) => weight[b].compareTo(weight[a]));
  final total = weight.fold<double>(0, (a, b) => a + b);
  final picked = <int>[];
  for (final bin in order) {
    // Ignore specks: a bucket needs a real share of the coloured pixels.
    if (weight[bin] <= 0 || weight[bin] < total * 0.04) break;
    final hue = bin * 10;
    final near = picked.any((p) {
      final d = (p * 10 - hue).abs() % 360;
      return (d > 180 ? 360 - d : d) < 24;
    });
    if (near) continue;
    picked.add(bin);
    if (picked.length == max) break;
  }
  return [
    for (final bin in picked)
      Color.fromARGB(
        255,
        (sum[bin][0] / sum[bin][3]).round().clamp(0, 255),
        (sum[bin][1] / sum[bin][3]).round().clamp(0, 255),
        (sum[bin][2] / sum[bin][3]).round().clamp(0, 255),
      ),
  ];
}
