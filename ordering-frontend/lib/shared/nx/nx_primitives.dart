import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/nocturne.dart';

/// Nocturne's small building blocks — the prototype's `.btn`, `.tag`, bars,
/// surface sections and hover rows. Everything reads `context.nx`.

enum NxButtonKind { primary, secondary, ghost, danger }

/// `.btn` — outlined primary (accent), secondary (divider), ghost (accent
/// text), or danger (the bad tone as an outline). Compact by default
/// (13px, 5×10 padding), as the prototype's toolbar buttons are.
class NxButton extends StatefulWidget {
  const NxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = NxButtonKind.secondary,
    this.trailingIcon,
    this.small = false,
    this.expand = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final NxButtonKind kind;

  /// 12px text, 4×9 padding — the in-panel buttons.
  final bool small;
  final bool expand;

  /// Overrides the text/border colour (e.g. a "Revoke" secondary in the bad tone).
  final Color? color;

  const NxButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.small = false,
    this.expand = false,
  }) : kind = NxButtonKind.primary,
       color = null;

  const NxButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.small = false,
    this.color,
  }) : kind = NxButtonKind.ghost,
       expand = false;

  @override
  State<NxButton> createState() => _NxButtonState();
}

class _NxButtonState extends State<NxButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final enabled = widget.onPressed != null;
    final (Color fg, Color? border, Color wash) = switch (widget.kind) {
      NxButtonKind.primary => (widget.color ?? n.accent, widget.color ?? n.accent, widget.color ?? n.accent),
      NxButtonKind.secondary => (widget.color ?? n.text, n.divider, n.text),
      NxButtonKind.ghost => (widget.color ?? n.accent, null, widget.color ?? n.accent),
      NxButtonKind.danger => (n.bad, n.bad, n.bad),
    };
    final hoverA = widget.kind == NxButtonKind.secondary ? 0.07 : 0.12;
    final downA = widget.kind == NxButtonKind.secondary ? 0.14 : 0.22;
    final bg = !enabled
        ? Colors.transparent
        : _down
        ? wash.withValues(alpha: downA)
        : _hover
        ? wash.withValues(alpha: hoverA)
        : Colors.transparent;
    final fontSize = widget.small ? 12.0 : 13.0;
    final pad = widget.kind == NxButtonKind.ghost
        ? EdgeInsets.symmetric(horizontal: widget.small ? 3 : 4, vertical: widget.small ? 3 : 4)
        : EdgeInsets.symmetric(horizontal: widget.small ? 9 : 10, vertical: widget.small ? 4 : 5);

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[Icon(widget.icon, size: fontSize + 2, color: fg), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: fg, height: 1.2),
          ),
        ),
        if (widget.trailingIcon != null) ...[const SizedBox(width: 6), Icon(widget.trailingIcon, size: fontSize + 1, color: fg)],
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = _down = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: widget.label,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: pad,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(NxRadius.md),
                border: border == null ? null : Border.all(color: border),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// `.btn.btn-icon` — a square icon-only button with a hover wash.
class NxIconButton extends StatefulWidget {
  const NxIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 34,
    this.iconSize = 18,
    this.color,
    this.bordered = false,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;

  /// `.btn-secondary` look (divider border) — the sidebar's sign-out button.
  final bool bordered;

  /// A small accent count in the top-right corner (the notifications bell).
  final int? badge;

  @override
  State<NxIconButton> createState() => _NxIconButtonState();
}

class _NxIconButtonState extends State<NxIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final badge = widget.badge;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Semantics(
            button: true,
            label: widget.tooltip,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _hover ? n.textAlpha(0.07) : Colors.transparent,
                borderRadius: BorderRadius.circular(NxRadius.md),
                border: widget.bordered ? Border.all(color: n.divider) : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(widget.icon, size: widget.iconSize, color: widget.color ?? n.n300),
                  if (badge != null && badge > 0)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 15),
                        height: 15,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(color: n.accent, borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: Text(
                          '$badge',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: n.bg, height: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A status tag — `font-size:11px; padding:2px 8px; radius 6px` on the
/// tone's tinted ground.
class NxTag extends StatelessWidget {
  const NxTag(this.label, {super.key, this.tone = Tone.neutral, this.small = false, this.fg, this.bg, this.mono = false});

  final String label;
  final Tone tone;

  /// 10px, 1×7 padding — tags inside list rows and grid cards.
  final bool small;
  final Color? fg;
  final Color? bg;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final (tfg, tbg) = context.nx.tone(tone);
    return Container(
      padding: small ? const EdgeInsets.symmetric(horizontal: 7, vertical: 1) : const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg ?? tbg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: small ? 10 : 11,
          color: fg ?? tfg,
          height: 1.35,
          fontFamily: mono ? NxText.mono : null,
        ),
      ),
    );
  }
}

/// The warn-tinted pill count on nav items and group headers.
class NxCountBadge extends StatelessWidget {
  const NxCountBadge(this.count, {super.key, this.tone = Tone.warn});

  final int count;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final (fg, _) = n.tone(tone);
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(color: fg.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg, height: 1)),
    );
  }
}

/// A thin horizontal meter. [marker] draws the "minimum" tick at 50%
/// (the prototype's stock-vs-min bar is scaled to twice the minimum).
class NxBar extends StatelessWidget {
  const NxBar({super.key, required this.fraction, this.color, this.height = 5, this.marker = false, this.track});

  final double fraction;
  final Color? color;
  final double height;
  final bool marker;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return SizedBox(
      height: marker ? height + 6 : height,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.none,
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(color: track ?? n.n800, borderRadius: BorderRadius.circular(height)),
            ),
            Container(
              width: box.maxWidth * f,
              height: height,
              decoration: BoxDecoration(color: color ?? n.a500, borderRadius: BorderRadius.circular(height)),
            ),
            if (marker)
              Positioned(
                left: box.maxWidth / 2,
                top: 0,
                bottom: 0,
                child: Tooltip(message: 'Minimum', child: Container(width: 1, color: n.n400)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A bar with its value label on the left (the table "bar" cell).
class NxLabeledBar extends StatelessWidget {
  const NxLabeledBar({super.key, required this.label, required this.fraction, this.color, this.labelColor, this.marker = false});

  final String label;
  final double fraction;
  final Color? color;
  final Color? labelColor;
  final bool marker;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Row(
      children: [
        if (label.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 34),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: labelColor ?? n.text, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        if (label.isNotEmpty) const SizedBox(width: 8),
        Expanded(child: NxBar(fraction: fraction, color: color, marker: marker)),
      ],
    );
  }
}

/// A surface panel: `background: surface; radius 8; shadow-sm`.
class NxSection extends StatelessWidget {
  const NxSection({super.key, required this.child, this.padding, this.clip = true, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool clip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? n.surface,
        borderRadius: BorderRadius.circular(NxRadius.md),
        boxShadow: n.shadowSm,
      ),
      child: child,
    );
  }
}

/// A full-width tappable row with the prototype's 4% text-colour hover wash
/// and an optional top rule (`border-top: 1px solid neutral-900`).
class NxHoverRow extends StatefulWidget {
  const NxHoverRow({super.key, required this.child, this.onTap, this.padding, this.topRule = true, this.bottomRule = false});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final bool topRule;
  final bool bottomRule;

  @override
  State<NxHoverRow> createState() => _NxHoverRowState();
}

class _NxHoverRowState extends State<NxHoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final rule = BorderSide(color: n.n900);
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _hover && widget.onTap != null ? n.textAlpha(0.04) : Colors.transparent,
            border: Border(
              top: widget.topRule ? rule : BorderSide.none,
              bottom: widget.bottomRule ? rule : BorderSide.none,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A rounded icon tile (list rows, grid cards, notifications, toasts).
class NxIconTile extends StatelessWidget {
  const NxIconTile({super.key, required this.icon, this.size = 32, this.iconSize = 17, this.fg, this.bg, this.radius = 8});

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? fg;
  final Color? bg;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg ?? n.n900, borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: PhosphorIcon(icon, size: iconSize, color: fg ?? n.n500),
    );
  }
}

/// Initials in a rounded square (the users table, the top bar).
class NxAvatar extends StatelessWidget {
  const NxAvatar({super.key, required this.name, this.size = 28, this.accent = false});

  final String name;
  final double size;
  final bool accent;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: accent ? n.a800 : n.n800, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: Text(
        initialsOf(name),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent ? n.a100 : n.n200),
      ),
    );
  }
}

/// A rule that fades to transparent over 48px at each end (`.hr`).
class NxFadeRule extends StatelessWidget {
  const NxFadeRule({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.nx.divider;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite && box.maxWidth > 0 ? box.maxWidth : 1000.0;
        final edge = (48 / w).clamp(0.0, 0.5);
        return Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.withValues(alpha: 0), c, c, c.withValues(alpha: 0)],
              stops: [0, edge, 1 - edge, 1],
            ),
          ),
        );
      },
    );
  }
}

/// Uppercase micro-label (`font-size:10–11px; letter-spacing .08em`).
class NxKicker extends StatelessWidget {
  const NxKicker(this.text, {super.key, this.color, this.size = 10});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: size, letterSpacing: size * 0.08, color: color ?? context.nx.n500, height: 1.3),
    );
  }
}

/// Tabular-figure text style helper.
const tabular = [FontFeature.tabularFigures()];
