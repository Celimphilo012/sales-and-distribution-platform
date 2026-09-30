import 'package:flutter/material.dart';

import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_primitives.dart';

/// The receive / transfer sheets' "Balance preview" panel — an accent-tinted
/// card with a kicker, showing what the movement will do before it is made.
class BalancePreview extends StatelessWidget {
  const BalancePreview({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NxRadius.md),
        boxShadow: n.shadowSm,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Nocturne.mix(n.a900, n.surface, 0.7), n.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NxKicker('Balance preview', color: n.a300),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// "before → after" in the preview's figures.
class BeforeAfter extends StatelessWidget {
  const BeforeAfter({super.key, required this.before, required this.after, this.delta, this.deltaColor, this.large = true});

  final String before;
  final String after;
  final String? delta;
  final Color? deltaColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        Text(before, style: TextStyle(fontSize: large ? 19 : 15, color: n.n400, fontFeatures: tabular)),
        Text('→', style: TextStyle(fontSize: large ? 15 : 12, color: n.n500)),
        Text(after, style: TextStyle(fontSize: large ? 23 : 15, fontWeight: FontWeight.w500, color: n.text, fontFeatures: tabular)),
        if (delta != null) Text(delta!, style: TextStyle(fontSize: 12, color: deltaColor ?? n.ok, fontFeatures: tabular)),
      ],
    );
  }
}
