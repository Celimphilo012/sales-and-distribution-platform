import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/nocturne.dart';
import '../../core/ui/root_navigator_key.dart';
import 'nx_primitives.dart';

/// Nocturne overlays: the right-hand SHEET (product, receive, transfer, count,
/// packing, role, report), the centred DIALOG (forms, confirmations, reviews)
/// and TOASTS. All open on the ROOT navigator so they sit above the shell.

// ─── Sheet ──────────────────────────────────────────────────────────────────

/// Opens a right-hand sheet: a fading scrim, a panel sliding in from the right
/// (480px; 760px when [wide]; full width on a phone), an uppercase [kicker]
/// and a close button. Resolves with whatever the sheet pops.
Future<T?> showNxSheet<T>(
  BuildContext context, {
  required String kicker,
  required WidgetBuilder builder,
  bool wide = false,
}) {
  final nav = rootNavigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
  return nav.push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (routeContext, animation, _) => _NxSheetFrame(kicker: kicker, wide: wide, animation: animation, builder: builder),
    ),
  );
}

class _NxSheetFrame extends StatelessWidget {
  const _NxSheetFrame({required this.kicker, required this.wide, required this.animation, required this.builder});

  final String kicker;
  final bool wide;
  final Animation<double> animation;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final screen = MediaQuery.of(context).size;
    final phone = screen.width < 600;
    final width = phone ? screen.width : (wide ? 760.0 : 480.0).clamp(0.0, screen.width);
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);

    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: curved,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: ColoredBox(color: n.n900.withValues(alpha: 0.55)),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: width,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: Material(
                color: n.bg,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: n.bg, boxShadow: n.shadowLg),
                  child: SafeArea(
                    left: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
                          child: Row(
                            children: [
                              Expanded(child: NxKicker(kicker, size: 11, color: n.n400)),
                              NxIconButton(
                                icon: PhosphorIconsRegular.x,
                                tooltip: 'Close',
                                size: 30,
                                iconSize: 16,
                                color: n.n400,
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: Builder(builder: builder)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The standard scrolling body of a sheet (16px padding).
class NxSheetBody extends StatelessWidget {
  const NxSheetBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

// ─── Dialog ─────────────────────────────────────────────────────────────────

/// Opens a centred Nocturne dialog (`.dialog`): radius 14, shadow-lg, a
/// blurred scrim, popping in. [width] 460 by default (560 forms, 720 audit).
Future<T?> showNxDialog<T>(BuildContext context, {required WidgetBuilder builder, double width = 460, bool dismissible = true}) {
  final nav = rootNavigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
  return nav.push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: dismissible,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (routeContext, animation, _) {
        final n = routeContext.nx;
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return Stack(
          children: [
            Positioned.fill(
              child: FadeTransition(
                opacity: curved,
                child: GestureDetector(
                  onTap: dismissible ? () => Navigator.of(routeContext).maybePop() : null,
                  child: ColoredBox(color: n.n900.withValues(alpha: 0.5)),
                ),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(curved),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.of(routeContext).size.height - 32),
                      child: Material(
                        color: n.surface,
                        borderRadius: BorderRadius.circular(NxRadius.lg),
                        clipBehavior: Clip.antiAlias,
                        child: DecoratedBox(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(NxRadius.lg), boxShadow: n.shadowLg),
                          child: Builder(builder: builder),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// The inside of a dialog: title (+ sub-line), scrolling body, action row.
class NxDialogFrame extends StatelessWidget {
  const NxDialogFrame({super.key, required this.title, this.sub, this.titleWidget, required this.body, this.actions = const []});

  final String title;
  final String? sub;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleWidget ??
              Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: n.text, height: 1.2)),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(sub!, style: TextStyle(fontSize: 12, color: n.n400)),
            ),
          const SizedBox(height: 10),
          Flexible(child: SingleChildScrollView(child: body)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// A yes/no confirmation. [danger] draws the confirm button in the bad tone.
Future<bool> showNxConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool danger = false,
}) async {
  final ok = await showNxDialog<bool>(
    context,
    builder: (ctx) => NxDialogFrame(
      title: title,
      body: Text(body, style: TextStyle(fontSize: 14, color: ctx.nx.text.withValues(alpha: 0.85), height: 1.5)),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
        NxButton(
          label: confirmLabel,
          kind: danger ? NxButtonKind.danger : NxButtonKind.primary,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// ─── Toasts ─────────────────────────────────────────────────────────────────

class NxToastAction {
  const NxToastAction(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;
}

class _ToastData {
  _ToastData(this.id, this.tone, this.title, this.message, this.action, this.duration);

  final int id;
  final Tone tone;
  final String title;
  final String? message;
  final NxToastAction? action;
  final Duration duration;
}

/// Hosts the app's toasts (mounted once in `MaterialApp.builder`, above every
/// route). Show one from anywhere with [NxToast.show].
class NxToastHost extends StatefulWidget {
  const NxToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<NxToastHost> createState() => _NxToastHostState();
}

class _NxToastHostState extends State<NxToastHost> {
  final List<_ToastData> _toasts = [];
  int _next = 0;

  @override
  void initState() {
    super.initState();
    NxToast._host = this;
  }

  @override
  void dispose() {
    if (NxToast._host == this) NxToast._host = null;
    super.dispose();
  }

  void _add(Tone tone, String title, String? message, NxToastAction? action, Duration duration) {
    final t = _ToastData(_next++, tone, title, message, action, duration);
    setState(() {
      _toasts.add(t);
      if (_toasts.length > 4) _toasts.removeAt(0);
    });
    Timer(duration, () => _remove(t.id));
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _toasts.removeWhere((t) => t.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.of(context).size.width < 600;
    return Stack(
      children: [
        widget.child,
        if (_toasts.isNotEmpty)
          Positioned(
            left: phone ? 12 : null,
            right: phone ? 12 : 16,
            top: phone ? 12 : null,
            bottom: phone ? null : 16,
            width: phone ? null : 360,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in _toasts)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _Toast(key: ValueKey(t.id), data: t, onClose: () => _remove(t.id)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Shows a toast: `NxToast.show(Tone.ok, 'Product created', 'P-1013 · Flour')`.
class NxToast {
  const NxToast._();

  static _NxToastHostState? _host;

  static void show(
    Tone tone,
    String title, [
    String? message,
    NxToastAction? action,
    Duration duration = const Duration(seconds: 5),
  ]) => _host?._add(tone, title, message, action, duration);

  static void ok(String title, [String? message, NxToastAction? action]) => show(Tone.ok, title, message, action);
  static void info(String title, [String? message, NxToastAction? action]) => show(Tone.info, title, message, action);
  static void warn(String title, [String? message]) => show(Tone.warn, title, message);
  static void error(String title, [String? message]) => show(Tone.bad, title, message);
}

class _Toast extends StatefulWidget {
  const _Toast({super.key, required this.data, required this.onClose});

  final _ToastData data;
  final VoidCallback onClose;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _life = AnimationController(vsync: this, duration: widget.data.duration)..forward();

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final (fg, bg) = n.tone(widget.data.tone);
    final icon = switch (widget.data.tone) {
      Tone.ok => PhosphorIconsFill.checkCircle,
      Tone.warn => PhosphorIconsFill.warning,
      Tone.bad => PhosphorIconsFill.xCircle,
      _ => PhosphorIconsFill.info,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
      child: Material(
        color: n.surface,
        borderRadius: BorderRadius.circular(NxRadius.md),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(NxRadius.md), boxShadow: n.shadowMd),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NxIconTile(icon: icon, size: 28, iconSize: 16, fg: fg, bg: bg),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.data.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                            if (widget.data.message != null && widget.data.message!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(widget.data.message!, style: TextStyle(fontSize: 12, color: n.n400)),
                              ),
                            if (widget.data.action != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: NxButton.ghost(
                                  label: widget.data.action!.label,
                                  small: true,
                                  trailingIcon: PhosphorIconsRegular.arrowRight,
                                  onPressed: () {
                                    widget.onClose();
                                    widget.data.action!.onPressed();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    NxIconButton(
                      icon: PhosphorIconsRegular.x,
                      tooltip: 'Dismiss',
                      size: 24,
                      iconSize: 13,
                      color: n.n500,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: _life,
                  builder: (context, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 1 - _life.value,
                      child: Container(height: 2, color: fg.withValues(alpha: 0.7)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
