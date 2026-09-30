import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_form.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../data/branding_api.dart';
import 'settings_head.dart';

/// Company branding (`settings.manage` to change): the logo and company name
/// printed at the top of every PDF / Excel export and pick list.
class BrandingSection extends ConsumerStatefulWidget {
  const BrandingSection({super.key, required this.canManage});

  final bool canManage;

  @override
  ConsumerState<BrandingSection> createState() => _BrandingSectionState();
}

class _BrandingSectionState extends ConsumerState<BrandingSection> {
  TextEditingController? _company;
  bool _busy = false;

  @override
  void dispose() {
    _company?.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task, String ok) async {
    setState(() => _busy = true);
    try {
      await task();
      ref.invalidate(brandingProvider);
      NxToast.ok(ok);
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
    await _run(() => ref.read(brandingApiProvider).uploadLogo(bytes, file.name), 'Logo updated');
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final branding = ref.watch(brandingProvider).value;
    final logo = ref.watch(brandingLogoProvider).value;
    if (branding != null && _company == null) _company = TextEditingController(text: branding.companyName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead('Branding', sub: 'Your company name and logo — on the browser tab, the top bar, the sign-in page, and every PDF / Excel export and pick list.'),
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(12), boxShadow: n.shadowSm),
              alignment: Alignment.center,
              child: logo != null
                  ? Padding(padding: const EdgeInsets.all(6), child: Image.memory(logo, fit: BoxFit.contain))
                  : Icon(PhosphorIconsBold.warehouse, size: 28, color: n.a300),
            ),
            if (widget.canManage)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NxButton(label: 'Upload logo', icon: PhosphorIconsRegular.uploadSimple, onPressed: _busy ? null : _upload),
                  if (branding?.hasLogo ?? false)
                    NxButton.ghost(
                      label: 'Use default',
                      color: n.n400,
                      onPressed: _busy ? null : () => _run(() => ref.read(brandingApiProvider).clearLogo(), 'Default logo restored'),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('PNG or JPEG, square, at least 128 × 128 px — it also becomes the browser tab icon.', style: TextStyle(fontSize: 11, color: n.n500)),
        const SizedBox(height: 14),
        SettingsNarrow(
          width: 380,
          child: NxField(
            label: 'Company name on reports',
            child: Row(
              children: [
                Expanded(child: NxInput(controller: _company, enabled: widget.canManage && !_busy)),
                if (widget.canManage) ...[
                  const SizedBox(width: 8),
                  NxButton.primary(
                    label: 'Save',
                    onPressed: _busy || _company == null
                        ? null
                        : () {
                            final name = _company!.text.trim();
                            if (name.isEmpty) return;
                            _run(() => ref.read(brandingApiProvider).setCompanyName(name), 'Company name saved');
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!widget.canManage) ...[
          const SizedBox(height: 10),
          Text('Changing these needs the settings.manage permission.', style: TextStyle(fontSize: 12, color: n.n500)),
        ],
      ],
    );
  }
}
