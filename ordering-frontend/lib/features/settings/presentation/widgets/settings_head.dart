import 'package:flutter/material.dart';

import '../../../../core/theme/nocturne.dart';

/// A settings panel's heading: title, optional one-line explanation, and an
/// optional action on the right.
class SettingsHead extends StatelessWidget {
  const SettingsHead(this.title, {super.key, this.sub, this.trailing});

  final String title;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: n.text)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub!, style: TextStyle(fontSize: 12, color: n.n400)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Form fields in a settings panel stay narrow, like the prototype's.
class SettingsNarrow extends StatelessWidget {
  const SettingsNarrow({super.key, required this.child, this.width = 420});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child),
  );
}
