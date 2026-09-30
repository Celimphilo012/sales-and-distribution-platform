import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/nocturne.dart';

/// Nocturne form controls — the prototype's `.field` / `.input` / `.seg` and
/// the chip multi-select, plus a select whose dropdown can be SEARCHED (for
/// long product and location lists: type part of a SKU, name or code).

/// `.field`: a 12px label (with a required star), the control, then an
/// optional hint or error line.
class NxField extends StatelessWidget {
  const NxField({super.key, required this.label, required this.child, this.required = false, this.hint, this.error});

  final String label;
  final Widget child;
  final bool required;
  final String? hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text.rich(
            TextSpan(
              text: label,
              children: [if (required) TextSpan(text: ' *', style: TextStyle(color: n.a300))],
            ),
            style: TextStyle(fontSize: 12, color: n.textAlpha(0.7), height: 1.3),
          ),
        ),
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error!, style: TextStyle(fontSize: 11, color: n.bad)),
          )
        else if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(hint!, style: TextStyle(fontSize: 11, color: n.n500)),
          ),
      ],
    );
  }
}

/// The `.input` box decoration shared by every control, so a text input, a
/// select and a search sit in a row looking identical.
BoxDecoration nxInputDecoration(Nocturne n, {bool focused = false, bool hover = false, bool error = false, bool enabled = true, Color? fill}) =>
    BoxDecoration(
      color: fill ?? n.surface,
      borderRadius: BorderRadius.circular(NxRadius.md),
      border: Border.all(
        color: error
            ? n.bad
            : focused
            ? n.accent
            : hover && enabled
            ? n.textAlpha(0.45)
            : n.divider,
      ),
    );

/// `.input` — a single-line (or multi-line) text box. [dense] is the 32px
/// toolbar height; the default is the 36px form height.
class NxInput extends StatefulWidget {
  const NxInput({
    super.key,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.prefixIcon,
    this.suffix,
    this.dense = false,
    this.enabled = true,
    this.obscure = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.error = false,
    this.autofocus = false,
    this.focusNode,
    this.textAlign = TextAlign.start,
    this.fill,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool dense;
  final bool enabled;
  final bool obscure;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool error;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextAlign textAlign;
  final Color? fill;

  /// A numeric input (digits and one decimal point, up to 3 places).
  static List<TextInputFormatter> decimals([int places = 3]) => [
    FilteringTextInputFormatter.allow(RegExp('^\\d*\\.?\\d{0,$places}')),
  ];

  @override
  State<NxInput> createState() => _NxInputState();
}

class _NxInputState extends State<NxInput> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  TextEditingController? _own;
  bool _hover = false;

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController(text: widget.initialValue));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final multi = widget.maxLines > 1 || (widget.minLines ?? 1) > 1;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.55,
        child: Container(
          constraints: BoxConstraints(minHeight: widget.dense ? 32 : 36),
          decoration: nxInputDecoration(
            n,
            focused: _focus.hasFocus,
            hover: _hover,
            error: widget.error,
            enabled: widget.enabled,
            fill: widget.fill,
          ),
          padding: EdgeInsets.only(left: widget.prefixIcon != null ? 0 : 10, right: widget.suffix != null ? 4 : 10),
          child: Row(
            crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (widget.prefixIcon != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  child: Icon(widget.prefixIcon, size: 14, color: n.n500),
                ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  obscureText: widget.obscure,
                  autofocus: widget.autofocus,
                  maxLines: widget.obscure ? 1 : widget.maxLines,
                  minLines: widget.minLines,
                  keyboardType: widget.keyboardType,
                  inputFormatters: widget.inputFormatters,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  textAlign: widget.textAlign,
                  cursorColor: n.accent,
                  style: TextStyle(fontSize: widget.dense ? 13 : 13.5, color: n.text, height: 1.35),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hintText: widget.placeholder,
                    hintStyle: TextStyle(fontSize: widget.dense ? 13 : 13.5, color: n.n500),
                    contentPadding: EdgeInsets.symmetric(vertical: multi ? 8 : (widget.dense ? 7 : 9)),
                  ),
                ),
              ),
              if (widget.suffix != null) widget.suffix!,
            ],
          ),
        ),
      ),
    );
  }
}

/// One option of an [NxSelect]. [search] is extra text matched when the list
/// is searched (e.g. a product's SKU while [label] shows its name).
class NxOption<T> {
  const NxOption(this.value, this.label, {this.sub, this.search, this.trailing, this.enabled = true});

  final T value;
  final String label;
  final String? sub;
  final String? search;
  final String? trailing;
  final bool enabled;

  bool matches(String q) {
    if (q.isEmpty) return true;
    final hay = '$label ${sub ?? ''} ${search ?? ''}'.toLowerCase();
    return q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).every(hay.contains);
  }
}

/// A select styled as `.input` with the prototype's caret. Its menu opens
/// under the box; with [searchable] the menu leads with a search field
/// (typing filters by label, sub-line and [NxOption.search]; ↑/↓ + Enter
/// pick). [emptyLabel] adds an "any"/none row mapping to `null`.
class NxSelect<T> extends StatefulWidget {
  const NxSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder = 'Select…',
    this.searchable = false,
    this.searchPlaceholder = 'Type to search',
    this.emptyLabel,
    this.dense = false,
    this.enabled = true,
    this.error = false,
    this.menuMaxHeight = 320,
  });

  final List<NxOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String placeholder;
  final bool searchable;
  final String searchPlaceholder;
  final String? emptyLabel;
  final bool dense;
  final bool enabled;
  final bool error;
  final double menuMaxHeight;

  @override
  State<NxSelect<T>> createState() => _NxSelectState<T>();
}

class _NxSelectState<T> extends State<NxSelect<T>> {
  final _link = LayerLink();
  final _overlay = OverlayPortalController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  bool _hover = false;
  int _highlight = 0;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<(T?, NxOption<T>?)> get _rows {
    final q = _search.text.trim();
    return [
      if (widget.emptyLabel != null && q.isEmpty) (null, null),
      for (final o in widget.options)
        if (o.matches(q)) (o.value, o),
    ];
  }

  void _open() {
    if (!widget.enabled) return;
    _search.clear();
    final rows = _rows;
    final current = rows.indexWhere((r) => r.$1 == widget.value);
    _highlight = current < 0 ? 0 : current;
    _overlay.show();
    setState(() {});
    if (widget.searchable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
    }
  }

  void _close() {
    _overlay.hide();
    setState(() {});
  }

  void _pick(T? value) {
    _close();
    widget.onChanged(value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final rows = _rows;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlight = (_highlight + 1).clamp(0, rows.isEmpty ? 0 : rows.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _highlight = (_highlight - 1).clamp(0, rows.isEmpty ? 0 : rows.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && rows.isNotEmpty) {
      final r = rows[_highlight.clamp(0, rows.length - 1)];
      if (r.$2?.enabled ?? true) _pick(r.$1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final selected = widget.options.where((o) => o.value == widget.value).firstOrNull;
    final label = selected?.label ?? (widget.value == null && widget.emptyLabel != null ? widget.emptyLabel! : null);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) => _menu(context),
        child: MouseRegion(
          cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: _overlay.isShowing ? _close : _open,
            child: Semantics(
              button: true,
              label: label ?? widget.placeholder,
              child: Opacity(
                opacity: widget.enabled ? 1 : 0.55,
                child: Container(
                  constraints: BoxConstraints(minHeight: widget.dense ? 32 : 36),
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  decoration: nxInputDecoration(
                    n,
                    focused: _overlay.isShowing,
                    hover: _hover,
                    error: widget.error,
                    enabled: widget.enabled,
                  ),
                  child: Row(
                    children: [
                      if (widget.searchable) ...[Icon(PhosphorIconsRegular.magnifyingGlass, size: 13, color: n.n500), const SizedBox(width: 7)],
                      Expanded(
                        child: Text(
                          label ?? widget.placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: widget.dense ? 13 : 13.5, color: label == null ? n.n500 : n.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(PhosphorIconsBold.caretDown, size: 10, color: n.n400),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) {
    final n = context.nx;
    final box = this.context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 280;
    final rows = _rows;
    final screen = MediaQuery.of(context).size;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final below = screen.height - origin.dy - (box?.size.height ?? 36) - 12;
    final openUp = below < 220 && origin.dy > below;

    return Stack(
      children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _close)),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: openUp ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: openUp ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, openUp ? -4 : 4),
          child: Material(
            type: MaterialType.transparency,
            child: Focus(
              onKeyEvent: _onKey,
              autofocus: !widget.searchable,
              child: Container(
                width: width < 240 ? 240 : width,
                constraints: BoxConstraints(maxHeight: widget.menuMaxHeight),
                decoration: BoxDecoration(
                  color: n.surface,
                  borderRadius: BorderRadius.circular(NxRadius.md),
                  boxShadow: n.shadowMd,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.searchable)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: NxInput(
                          controller: _search,
                          focusNode: _searchFocus,
                          dense: true,
                          prefixIcon: PhosphorIconsRegular.magnifyingGlass,
                          placeholder: widget.searchPlaceholder,
                          fill: n.bg,
                          onChanged: (_) => setState(() => _highlight = 0),
                          onSubmitted: (_) {
                            final r = _rows;
                            if (r.isNotEmpty) _pick(r[_highlight.clamp(0, r.length - 1)].$1);
                          },
                        ),
                      ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Text('No matches', style: TextStyle(fontSize: 12, color: n.n400)),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final (value, o) = rows[i];
                            final isSel = value == widget.value;
                            final hi = i == _highlight;
                            final enabled = o?.enabled ?? true;
                            return MouseRegion(
                              onEnter: (_) => setState(() => _highlight = i),
                              cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: enabled ? () => _pick(value) : null,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSel ? n.a900 : (hi ? n.textAlpha(0.06) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Opacity(
                                    opacity: enabled ? 1 : 0.45,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                o?.label ?? widget.emptyLabel!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 13, color: isSel ? n.a200 : n.text),
                                              ),
                                              if (o?.sub != null)
                                                Text(
                                                  o!.sub!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 11, color: n.n500),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (o?.trailing != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            o!.trailing!,
                                            style: TextStyle(fontSize: 11, color: n.n400, fontFeatures: const [FontFeature.tabularFigures()]),
                                          ),
                                        ],
                                        if (isSel) ...[const SizedBox(width: 6), Icon(PhosphorIconsBold.check, size: 12, color: n.a300)],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.seg` — a joined row of options; the chosen one is tinted accent.
class NxSeg<T> extends StatelessWidget {
  const NxSeg({super.key, required this.options, required this.value, required this.onChanged, this.small = true, this.iconOnly = false});

  /// (value, label, icon?)
  final List<(T, String, IconData?)> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool small;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(NxRadius.md), border: Border.all(color: n.divider)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: n.divider),
              _SegOption(
                label: options[i].$2,
                icon: options[i].$3,
                iconOnly: iconOnly,
                selected: options[i].$1 == value,
                small: small,
                onTap: onChanged == null ? null : () => onChanged!(options[i].$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegOption extends StatefulWidget {
  const _SegOption({required this.label, required this.selected, required this.small, this.icon, this.iconOnly = false, this.onTap});

  final String label;
  final IconData? icon;
  final bool iconOnly;
  final bool selected;
  final bool small;
  final VoidCallback? onTap;

  @override
  State<_SegOption> createState() => _SegOptionState();
}

class _SegOptionState extends State<_SegOption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final color = widget.selected ? n.a200 : n.n400;
    final child = widget.iconOnly
        ? Icon(widget.icon, size: 15, color: color)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 14, color: color), const SizedBox(width: 5)],
              Text(widget.label, style: TextStyle(fontSize: widget.small ? 12 : 13, color: color)),
            ],
          );
    return Tooltip(
      message: widget.iconOnly ? widget.label : '',
      child: MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Semantics(
            button: true,
            selected: widget.selected,
            label: widget.label,
            child: Container(
              padding: widget.iconOnly
                  ? const EdgeInsets.symmetric(horizontal: 9, vertical: 6)
                  : EdgeInsets.symmetric(horizontal: widget.small ? 10 : 14, vertical: widget.small ? 6 : 7),
              color: widget.selected ? n.a900 : (_hover ? n.textAlpha(0.07) : Colors.transparent),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill chip that toggles (the multi-select filter and form fields).
class NxChipToggle extends StatelessWidget {
  const NxChipToggle({super.key, required this.label, required this.selected, required this.onTap, this.showCheck = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? n.a900 : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? n.accent : n.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showCheck) ...[
                  Icon(selected ? PhosphorIconsBold.check : PhosphorIconsBold.plus, size: 11, color: selected ? n.a200 : n.n400),
                  const SizedBox(width: 5),
                ],
                Text(label, style: TextStyle(fontSize: 12, color: selected ? n.a200 : n.n400)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The filled check-square toggle (`ph-fill ph-check-square`).
class NxCheckToggle extends StatelessWidget {
  const NxCheckToggle({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Semantics(
          checked: value,
          label: label,
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square,
                  size: 18,
                  color: value ? n.accent : n.n500,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(label, style: TextStyle(fontSize: 13, color: n.text))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A form laid out in two columns (one on a phone) — the prototype's
/// `grid-template-columns: repeat(2, 1fr)` form grid. Wrap a field in
/// [NxSpan2] to make it span both columns.
class NxFormGrid extends StatelessWidget {
  const NxFormGrid({super.key, required this.children, this.gap = 12});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.of(context).size.width < 600;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = phone ? 1 : 2;
        final cell = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in children) SizedBox(width: c is NxSpan2 || cols == 1 ? box.maxWidth : cell, child: c),
          ],
        );
      },
    );
  }
}

/// Marks a field in an [NxFormGrid] as full-width.
class NxSpan2 extends StatelessWidget {
  const NxSpan2({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
