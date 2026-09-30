import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/brand_fonts.dart';
import '../../../../core/theme/brand_palette.dart';
import '../../../../core/theme/logo_palette.dart';
import '../../../../core/theme/nocturne.dart';
import '../../../../shared/export/report_export.dart';
import '../../../../shared/nx/nx_form.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../data/branding_api.dart';
import '../../data/delivery_settings_api.dart';
import 'settings_head.dart';

/// Ready-made brand colours (the first keeps the built-in violet).
const kBrandPresets = <(String, String?)>[
  ('Violet (built-in)', null),
  ('Indigo', '#3F51B5'),
  ('Ocean', '#0B6FB8'),
  ('Teal', '#0E7C66'),
  ('Emerald', '#1E9E57'),
  ('Lime', '#7CB518'),
  ('Amber', '#E0A100'),
  ('Orange', '#E8702A'),
  ('Crimson', '#C0283C'),
  ('Rose', '#D63F7A'),
  ('Plum', '#8E3FA8'),
  ('Slate', '#4A5A70'),
];

/// Font pairings that work well together: (name, heading, body).
const kFontPairings = <(String, String, String)>[
  ('Modern', 'Inter', 'Inter'),
  ('Corporate', 'Montserrat', 'Open Sans'),
  ('Friendly', 'Poppins', 'Nunito Sans'),
  ('Editorial', 'Playfair Display', 'Lato'),
  ('Classic', 'Merriweather', 'Source Sans 3'),
  ('Technical', 'IBM Plex Sans', 'IBM Plex Sans'),
];

/// The colours suggested by the uploaded logo (see [logoPalette]).
final _logoColorsProvider = FutureProvider.autoDispose.family<List<Color>, Uint8List>((ref, bytes) async {
  try {
    return await logoPalette(bytes);
  } catch (_) {
    return const [];
  }
});

enum _Tab {
  identity('Identity', PhosphorIconsRegular.identificationBadge),
  colour('Colour', PhosphorIconsRegular.palette),
  type('Typography', PhosphorIconsRegular.textAa),
  letterhead('Letterhead', PhosphorIconsRegular.fileText),
  email('Email signature', PhosphorIconsRegular.envelopeSimple);

  const _Tab(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _letterheadLabels = {
  'address': ('Address', 'Plot 12, Main Street, Mbabane'),
  'phone': ('Phone', '+268 2404 0000'),
  'email': ('Email', 'orders@company.co.sz'),
  'website': ('Website', 'www.company.co.sz'),
  'registration': ('Registration / VAT', 'Reg. 123/2020 · VAT 45678'),
  'footer': ('Footer line', 'Goods remain the property of … until paid in full.'),
};

/// Company branding (`settings.manage` to change) — the brand kit: name,
/// tagline and logo; the brand colour the whole console's accent is
/// generated from; approved heading / body fonts; the letterhead on PDF
/// documents; and the email signature. A live preview shows each change
/// before it is saved.
class BrandingSection extends ConsumerStatefulWidget {
  const BrandingSection({super.key, required this.canManage});

  final bool canManage;

  @override
  ConsumerState<BrandingSection> createState() => _BrandingSectionState();
}

class _BrandingSectionState extends ConsumerState<BrandingSection> {
  _Tab _tab = _Tab.identity;
  bool _busy = false;
  bool _seeded = false;
  bool? _previewDark;

  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _hex = TextEditingController();
  final _signature = TextEditingController();
  final _lh = {for (final f in Letterhead.fields) f: TextEditingController()};
  Color? _color;
  String _heading = kDefaultBrandFont;
  String _body = kDefaultBrandFont;

  @override
  void dispose() {
    for (final c in [_name, _tagline, _hex, _signature, ..._lh.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(Branding b) {
    _seeded = true;
    _name.text = b.companyName;
    _tagline.text = b.tagline ?? '';
    _color = BrandPalette.parse(b.brandColor);
    _hex.text = b.brandColor ?? '';
    _heading = b.headingFont ?? kDefaultBrandFont;
    _body = b.bodyFont ?? kDefaultBrandFont;
    _signature.text = b.emailSignature ?? '';
    for (final f in Letterhead.fields) {
      _lh[f]!.text = b.letterhead[f] ?? '';
    }
  }

  Future<void> _run(Future<void> Function(BrandingApi api) task, String ok) async {
    setState(() => _busy = true);
    try {
      await task(ref.read(brandingApiProvider));
      ref.invalidate(brandingProvider);
      NxToast.ok(ok, 'Everyone sees the change from their next screen.');
    } on AppError catch (e) {
      NxToast.error('Not saved', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _run((api) => api.uploadLogo(bytes, file.name), 'Logo updated');
  }

  void _pickColor(Color? c) => setState(() {
    _color = c;
    _hex.text = c == null ? '' : BrandPalette.hex(c);
  });

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final branding = ref.watch(brandingProvider).value;
    final logo = ref.watch(brandingLogoProvider).value;
    if (branding != null && !_seeded) _seed(branding);
    final dark = _previewDark ?? n.isDark;

    final editor = switch (_tab) {
      _Tab.identity => _identity(logo, branding),
      _Tab.colour => _colour(logo),
      _Tab.type => _typography(),
      _Tab.letterhead => _letterhead(),
      _Tab.email => _email(),
    };
    final preview = switch (_tab) {
      _Tab.identity || _Tab.colour || _Tab.type => _ConsolePreview(
        color: _color,
        heading: _heading,
        body: _body,
        name: _name.text.trim().isEmpty ? 'Your company' : _name.text.trim(),
        tagline: _tagline.text.trim(),
        logo: logo,
        dark: dark,
        onDark: (d) => setState(() => _previewDark = d),
      ),
      _Tab.letterhead => _LetterheadPreview(
        color: _color,
        name: _name.text.trim(),
        tagline: _tagline.text.trim(),
        logo: logo,
        values: {for (final e in _lh.entries) e.key: e.value.text.trim()},
      ),
      _Tab.email => _EmailPreview(
        color: _color,
        heading: _heading,
        body: _body,
        name: _name.text.trim(),
        tagline: _tagline.text.trim(),
        signature: _signature.text.trim(),
        values: {for (final e in _lh.entries) e.key: e.value.text.trim()},
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead(
          'Branding',
          sub: 'Your company’s look — name, colour, fonts, letterhead and email signature. The console, sign-in page, documents, labels and emails all follow it.',
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: NxSeg<_Tab>(
            small: false,
            options: [for (final t in _Tab.values) (t, t.label, t.icon)],
            value: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 820;
            if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [editor, const SizedBox(height: 18), preview]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: editor),
                const SizedBox(width: 22),
                SizedBox(width: 400, child: preview),
              ],
            );
          },
        ),
        if (!widget.canManage) ...[
          const SizedBox(height: 12),
          Text('Changing these needs the settings.manage permission.', style: TextStyle(fontSize: 12, color: n.n500)),
        ],
      ],
    );
  }

  // ─── Tabs ─────────────────────────────────────────────────────────────────

  Widget _save(String label, VoidCallback onPressed) => Align(
    alignment: Alignment.centerLeft,
    child: NxButton.primary(label: _busy ? 'Saving…' : label, icon: PhosphorIconsRegular.check, onPressed: _busy || !widget.canManage ? null : onPressed),
  );

  Widget _label(String text, {String? sub}) {
    final n = context.nx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 11.5, color: n.n500, height: 1.4)),
        ],
      ),
    );
  }

  Widget _identity(Uint8List? logo, Branding? branding) {
    final n = context.nx;
    final can = widget.canManage && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Logo', sub: 'PNG or JPEG, square, at least 128 × 128 px. Also the browser-tab icon and on every document.'),
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(14), boxShadow: n.shadowSm),
              alignment: Alignment.center,
              child: logo != null
                  ? Padding(padding: const EdgeInsets.all(8), child: Image.memory(logo, fit: BoxFit.contain))
                  : Icon(PhosphorIconsBold.warehouse, size: 30, color: n.a300),
            ),
            if (widget.canManage)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NxButton(label: 'Upload logo', icon: PhosphorIconsRegular.uploadSimple, onPressed: can ? _upload : null),
                  if (branding?.hasLogo ?? false)
                    NxButton.ghost(
                      label: 'Use default',
                      color: n.n400,
                      onPressed: can ? () => _run((api) => api.clearLogo(), 'Default logo restored') : null,
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 18),
        SettingsNarrow(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxField(
                label: 'Company name',
                child: NxInput(controller: _name, enabled: can, onChanged: (_) => setState(() {})),
              ),
              const SizedBox(height: 12),
              NxField(
                label: 'Tagline (optional)',
                hint: 'Under the name on the sign-in page, the top bar, documents and emails.',
                child: NxInput(
                  controller: _tagline,
                  enabled: can,
                  placeholder: 'e.g. Wholesale distribution · Mbabane',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _save('Save identity', () {
          final name = _name.text.trim();
          if (name.isEmpty) {
            NxToast.warn('Company name is required');
            return;
          }
          _run((api) => api.setIdentity(companyName: name, tagline: _tagline.text.trim()), 'Identity saved');
        }),
      ],
    );
  }

  Widget _swatch(Color? c, String label, {Color? fallback}) {
    final n = context.nx;
    final shown = c ?? fallback ?? Nocturne.dark.accent;
    final selected = c == null ? _color == null : _color?.toARGB32() == c.toARGB32();
    return Tooltip(
      message: c == null ? label : '$label · ${BrandPalette.hex(c)}',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: widget.canManage && !_busy ? () => _pickColor(c) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? n.text : Colors.transparent, width: 2)),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: shown, boxShadow: n.shadowSm),
            child: selected ? Icon(PhosphorIconsBold.check, size: 14, color: shown.computeLuminance() > 0.45 ? n.n900 : n.n100) : null,
          ),
        ),
      ),
    );
  }

  Widget _colour(Uint8List? logo) {
    final n = context.nx;
    final can = widget.canManage && !_busy;
    final fromLogo = logo == null ? null : ref.watch(_logoColorsProvider(logo));
    Widget ramp(Nocturne base, String label) {
      final t = base.withBrand(_color);
      return Row(
        children: [
          SizedBox(width: 44, child: Text(label, style: TextStyle(fontSize: 11, color: n.n500))),
          for (final c in t.accentRamp)
            Expanded(
              child: Container(height: 22, margin: const EdgeInsets.only(right: 3), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Presets'),
        Wrap(spacing: 4, runSpacing: 4, children: [for (final p in kBrandPresets) _swatch(BrandPalette.parse(p.$2), p.$1)]),
        const SizedBox(height: 16),
        _label('From your logo', sub: logo == null ? 'Upload a logo on the Identity tab to get colours taken from it.' : 'The logo’s main colours, most prominent first.'),
        if (fromLogo != null)
          fromLogo.when(
            loading: () => const SizedBox(height: 38, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
            error: (_, _) => const SizedBox.shrink(),
            data: (colors) => colors.isEmpty
                ? Text('No strong colours found in the logo.', style: TextStyle(fontSize: 12, color: n.n400))
                : Wrap(spacing: 4, runSpacing: 4, children: [for (final (i, c) in colors.indexed) _swatch(c, i == 0 ? 'Main logo colour' : 'Logo colour ${i + 1}')]),
          ),
        const SizedBox(height: 16),
        _label('Custom', sub: 'Any colour as a hex code, e.g. from your brand guidelines.'),
        Row(
          children: [
            SizedBox(
              width: 150,
              child: NxInput(
                controller: _hex,
                enabled: can,
                placeholder: '#0E7C66',
                prefixIcon: PhosphorIconsRegular.hash,
                onSubmitted: (v) {
                  final c = BrandPalette.parse(v);
                  c == null ? NxToast.warn('Not a colour', 'Use six hex digits, like #0E7C66.') : _pickColor(c);
                },
              ),
            ),
            const SizedBox(width: 8),
            NxButton(
              label: 'Apply',
              onPressed: can
                  ? () {
                      final c = BrandPalette.parse(_hex.text);
                      c == null ? NxToast.warn('Not a colour', 'Use six hex digits, like #0E7C66.') : _pickColor(c);
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _label('Generated shades', sub: 'Every shade is tuned to the brightness of the built-in palette, so text stays readable in dark and light mode — whatever colour you pick.'),
        ramp(Nocturne.dark, 'Dark'),
        const SizedBox(height: 4),
        ramp(Nocturne.light, 'Light'),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _save('Save colour', () => _run((api) => api.setIdentity(brandColor: _color == null ? '' : BrandPalette.hex(_color!)), 'Brand colour saved')),
            if (_color != null) NxButton.ghost(label: 'Back to built-in', color: n.n400, onPressed: can ? () => _pickColor(null) : null),
          ],
        ),
      ],
    );
  }

  Widget _typography() {
    final n = context.nx;
    final can = widget.canManage && !_busy;
    final options = [for (final f in kBrandFonts) NxOption(f, f, sub: kSerifBrandFonts.contains(f) ? 'Serif' : 'Sans-serif')];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Pairings', sub: 'Tried-and-tested combinations — or choose each font below.'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in kFontPairings)
              NxChipToggle(
                label: p.$1,
                selected: _heading == p.$2 && _body == p.$3,
                onTap: can
                    ? () => setState(() {
                        _heading = p.$2;
                        _body = p.$3;
                      })
                    : () {},
              ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsNarrow(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxField(
                label: 'Heading font',
                hint: 'Page titles, headings and the company name.',
                child: NxSelect<String>(options: options, value: _heading, enabled: can, onChanged: (v) => setState(() => _heading = v ?? kDefaultBrandFont)),
              ),
              const SizedBox(height: 12),
              NxField(
                label: 'Body font',
                hint: 'Everything else — tables, forms, buttons.',
                child: NxSelect<String>(options: options, value: _body, enabled: can, onChanged: (v) => setState(() => _body = v ?? kDefaultBrandFont)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(NxRadius.lg), boxShadow: n.shadowSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aa', style: brandFontSample(_heading, size: 40, color: n.text)),
              Text('Stock you can trust', style: brandFontSample(_heading, size: 20, color: n.text)),
              const SizedBox(height: 6),
              Text(
                'Receive, count and move stock with a full audit trail. 1,284 units across 36 locations.',
                style: brandFontSample(_body, size: 13, weight: FontWeight.w400, color: n.n300),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Applies to the console and emails. PDF documents use a standard print font so they open the same everywhere.', style: TextStyle(fontSize: 11.5, color: n.n500)),
        const SizedBox(height: 16),
        _save('Save fonts', () => _run((api) => api.setIdentity(headingFont: _heading, bodyFont: _body), 'Fonts saved')),
      ],
    );
  }

  Widget _letterhead() {
    final can = widget.canManage && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Letterhead', sub: 'Printed on every PDF report and pick list; the contact details also close every email. Leave a line empty to leave it out.'),
        SettingsNarrow(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in Letterhead.fields) ...[
                NxField(
                  label: _letterheadLabels[f]!.$1,
                  child: NxInput(
                    controller: _lh[f],
                    enabled: can,
                    placeholder: _letterheadLabels[f]!.$2,
                    maxLines: f == 'address' || f == 'footer' ? 2 : 1,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        _save('Save letterhead', () => _run((api) => api.setIdentity(letterhead: {for (final e in _lh.entries) e.key: e.value.text.trim()}), 'Letterhead saved')),
      ],
    );
  }

  Widget _email() {
    final n = context.nx;
    final can = widget.canManage && !_busy;
    final me = ref.watch(authProvider).value?.user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Email signature', sub: 'Closes every email the system sends — approvals, one-time codes and alerts — above your letterhead contact line.'),
        SettingsNarrow(
          width: 520,
          child: NxInput(
            controller: _signature,
            enabled: can,
            maxLines: 6,
            minLines: 4,
            placeholder: 'Kind regards,\nThe Operations Team\nAcme Distribution',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 6),
        Text('Emails are set in your brand fonts where the reader’s email app allows, and fall back to a similar standard font.', style: TextStyle(fontSize: 11.5, color: n.n500)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _save('Save signature', () => _run((api) => api.setIdentity(emailSignature: _signature.text.trim()), 'Email signature saved')),
            if (me != null && widget.canManage)
              NxButton(
                label: 'Send me a test email',
                icon: PhosphorIconsRegular.paperPlaneTilt,
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await ref.read(deliverySettingsApiProvider).sendTest(channel: 'EMAIL', to: me.email);
                          NxToast.ok('Test email sent', 'To ${me.email} — with the saved branding.');
                        } on AppError catch (e) {
                          NxToast.error('Not sent', e.message);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Previews ───────────────────────────────────────────────────────────────

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(PhosphorIconsRegular.eye, size: 14, color: n.n400),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: n.n300, letterSpacing: 0.3))),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

Widget _mark(Uint8List? logo, String name, Color border, Color fg, {double size = 28}) => logo != null
    ? ClipRRect(borderRadius: BorderRadius.circular(size * 0.27), child: SizedBox(width: size, height: size, child: Image.memory(logo, fit: BoxFit.contain)))
    : Container(
        width: size,
        height: size,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * 0.27), border: Border.all(color: border)),
        alignment: Alignment.center,
        child: Text(name.isEmpty ? 'W' : name[0].toUpperCase(), style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w700, color: fg)),
      );

/// A miniature console drawn with the REAL theme the draft settings produce.
class _ConsolePreview extends StatelessWidget {
  const _ConsolePreview({
    required this.color,
    required this.heading,
    required this.body,
    required this.name,
    required this.tagline,
    required this.logo,
    required this.dark,
    required this.onDark,
  });

  final Color? color;
  final String heading;
  final String body;
  final String name;
  final String tagline;
  final Uint8List? logo;
  final bool dark;
  final ValueChanged<bool> onDark;

  @override
  Widget build(BuildContext context) {
    final theme = dark ? AppTheme.dark(brand: color, headingFont: heading, bodyFont: body) : AppTheme.light(brand: color, headingFont: heading, bodyFont: body);
    return _PreviewFrame(
      title: 'PREVIEW · CONSOLE',
      trailing: NxSeg<bool>(
        options: const [(true, 'Dark', null), (false, 'Light', null)],
        value: dark,
        onChanged: onDark,
      ),
      child: Theme(
        data: theme,
        child: Builder(
          builder: (context) {
            final n = context.nx;
            final tt = Theme.of(context).textTheme;
            Widget navItem(String label, IconData icon, {bool on = false}) => Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: on ? n.a900 : null, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: on ? n.a200 : n.n400),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(fontSize: 10.5, color: on ? n.a100 : n.n300))),
                ],
              ),
            );
            return DefaultTextStyle(
              style: tt.bodyMedium!,
              child: Container(
                decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(NxRadius.lg), boxShadow: n.shadowMd),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.divider))),
                      child: Row(
                        children: [
                          _mark(logo, name, n.accent, n.accent),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall),
                                if (tagline.isNotEmpty) Text(tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(fontSize: 10.5)),
                              ],
                            ),
                          ),
                          Icon(PhosphorIconsRegular.bell, size: 15, color: n.n400),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 122,
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              navItem('Dashboard', PhosphorIconsRegular.squaresFour),
                              navItem('Receiving', PhosphorIconsRegular.boxArrowDown, on: true),
                              navItem('Inventory', PhosphorIconsRegular.cube),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 12, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Stock Receiving', style: tt.headlineSmall?.copyWith(fontSize: 17)),
                                const SizedBox(height: 2),
                                Text('Increases on-hand at the slot.', style: tt.bodySmall?.copyWith(fontSize: 10.5)),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: n.surface, borderRadius: BorderRadius.circular(NxRadius.md)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('BALANCE PREVIEW', style: tt.labelSmall?.copyWith(fontSize: 9, letterSpacing: 1, color: n.a300)),
                                      const SizedBox(height: 2),
                                      Text('120 → 150', style: tt.titleLarge?.copyWith(fontSize: 18)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    NxButton.primary(label: 'Receive', small: true, icon: PhosphorIconsRegular.boxArrowDown, onPressed: () {}),
                                    NxButton(label: 'Cancel', small: true, onPressed: () {}),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Wrap(spacing: 5, runSpacing: 5, children: [NxTag('Active', tone: Tone.ok, small: true), NxTag('Brand', tone: Tone.accent, small: true), NxTag('Info', tone: Tone.info, small: true)]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A PDF report's first page, as the letterhead draft prints it.
class _LetterheadPreview extends StatelessWidget {
  const _LetterheadPreview({required this.color, required this.name, required this.tagline, required this.logo, required this.values});

  final Color? color;
  final String name;
  final String tagline;
  final Uint8List? logo;
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    const paper = Nocturne.light;
    final c = ExportBranding(company: name, subtitle: '', color: color).colors;
    Color col(PdfColor p) => Color(p.toInt());
    final deep = col(c.deep);
    final accent = col(c.accent);
    final pale = col(c.pale);
    final contact = [for (final f in ['address', 'phone', 'email', 'website']) if ((values[f] ?? '').isNotEmpty) values[f]!];
    final small = [values['registration'], values['footer']].whereType<String>().where((x) => x.isNotEmpty).join('   |   ');
    TextStyle t(double size, {Color? color, FontWeight w = FontWeight.w400}) => TextStyle(fontSize: size, color: color ?? paper.text, fontWeight: w, fontFamily: 'Helvetica');

    return _PreviewFrame(
      title: 'PREVIEW · PDF REPORT',
      child: AspectRatio(
        aspectRatio: 0.74,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          decoration: BoxDecoration(color: paper.surface, borderRadius: BorderRadius.circular(4), boxShadow: context.nx.shadowMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  logo != null
                      ? _mark(logo, name, deep, deep, size: 26)
                      : Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: deep, borderRadius: BorderRadius.circular(6)),
                          alignment: Alignment.center,
                          child: Text(name.isEmpty ? 'W' : name[0].toUpperCase(), style: t(13, color: col(c.mark), w: FontWeight.w700)),
                        ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? 'Your company' : name, style: t(10, w: FontWeight.w700)),
                        if (tagline.isNotEmpty) Text(tagline, style: t(6.5, color: accent)),
                        Text('Mbabane Central · Generated today', style: t(6, color: paper.n500)),
                      ],
                    ),
                  ),
                  if (contact.isNotEmpty)
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [for (final l in contact) Text(l, style: t(5.8, color: paper.n500))]),
                ],
              ),
              const SizedBox(height: 7),
              Container(height: 1.4, color: accent),
              const SizedBox(height: 10),
              Text('Inventory valuation', style: t(12, w: FontWeight.w700)),
              Text('On-hand stock at cost, by product.', style: t(6.5, color: paper.n500)),
              const SizedBox(height: 8),
              Container(
                color: deep,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  children: [
                    for (final h in ['Product', 'On hand', 'Value'])
                      Expanded(child: Text(h, textAlign: h == 'Product' ? TextAlign.left : TextAlign.right, style: t(6.5, color: paper.surface, w: FontWeight.w700))),
                  ],
                ),
              ),
              for (final (i, r) in [('Body Lotion 500ml', '120', 'E 4,800'), ('Bamboo Soap Dish', '8,000', 'E 32,000'), ('Matte Lip Balm', '640', 'E 3,840')].indexed)
                Container(
                  color: i.isOdd ? pale : null,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(r.$1, style: t(6.5))),
                      Expanded(child: Text(r.$2, textAlign: TextAlign.right, style: t(6.5))),
                      Expanded(child: Text(r.$3, textAlign: TextAlign.right, style: t(6.5))),
                    ],
                  ),
                ),
              const Spacer(),
              if (small.isNotEmpty) ...[
                Container(height: 0.5, color: paper.n800),
                const SizedBox(height: 3),
                Text(small, style: t(5.5, color: paper.n600)),
                const SizedBox(height: 2),
              ],
              Row(
                children: [
                  Expanded(child: Text('${name.isEmpty ? 'Your company' : name} | Inventory valuation', style: t(5.5, color: paper.n600))),
                  Text('Page 1 of 1', style: t(5.5, color: paper.n600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A notification email, as the saved-to-be branding dresses it.
class _EmailPreview extends StatelessWidget {
  const _EmailPreview({
    required this.color,
    required this.heading,
    required this.body,
    required this.name,
    required this.tagline,
    required this.signature,
    required this.values,
  });

  final Color? color;
  final String heading;
  final String body;
  final String name;
  final String tagline;
  final String signature;
  final Map<String, String> values;

  /// The accent darkened until white text on it passes 4.5:1 (as the server does for buttons).
  static Color _darkForWhite(Color c) {
    var x = c;
    while (1.05 / (x.computeLuminance() + 0.05) < 4.5) {
      x = Color.fromARGB(255, (x.r * 255 * 0.9).round(), (x.g * 255 * 0.9).round(), (x.b * 255 * 0.9).round());
    }
    return x;
  }

  @override
  Widget build(BuildContext context) {
    const paper = Nocturne.light;
    const ink = Nocturne.dark;
    final accent = color ?? paper.a500;
    final contact = [for (final f in ['address', 'phone', 'email', 'website']) if ((values[f] ?? '').isNotEmpty) values[f]!];
    final shownName = name.isEmpty ? 'Your company' : name;
    TextStyle b(double size, {Color? color, FontWeight w = FontWeight.w400}) => brandFontSample(body, size: size, weight: w, color: color ?? paper.text);
    TextStyle h(double size, {Color? color}) => brandFontSample(heading, size: size, weight: FontWeight.w600, color: color ?? paper.text);

    return _PreviewFrame(
      title: 'PREVIEW · EMAIL',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: paper.bg, borderRadius: BorderRadius.circular(NxRadius.md), boxShadow: context.nx.shadowMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(color: ink.bg, border: Border(bottom: BorderSide(color: accent, width: 3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shownName, style: h(13, color: paper.surface)),
                  if (tagline.isNotEmpty) Text(tagline, style: b(9, color: ink.n300)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(color: paper.surface, border: Border(left: BorderSide(color: accent, width: 3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adjustment approved', style: h(15)),
                  const SizedBox(height: 6),
                  Text('Your request to adjust Body Lotion 500ml at A-02-03 was approved. Stock has been updated.', style: b(10.5)),
                  const SizedBox(height: 10),
                  Container(
                    color: _darkForWhite(accent),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text('Open the adjustment →', style: b(10, color: paper.surface, w: FontWeight.w600)),
                  ),
                  if (signature.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(height: 1, color: paper.n800),
                    const SizedBox(height: 8),
                    Container(width: 20, height: 2.5, color: accent),
                    const SizedBox(height: 6),
                    Text(signature, style: b(10, w: FontWeight.w400)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (contact.isNotEmpty) Text(contact.join(' · '), style: b(8.5)),
            if ((values['registration'] ?? '').isNotEmpty) Text(values['registration']!, style: b(8.5, color: paper.n500)),
            Text('This is an automated message from $shownName · please do not reply.', style: b(8.5, color: paper.n500)),
          ],
        ),
      ),
    );
  }
}
