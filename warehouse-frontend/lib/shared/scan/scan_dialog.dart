import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/nocturne.dart';
import '../nx/nx_form.dart';
import '../nx/nx_overlays.dart';
import '../nx/nx_primitives.dart';
import 'scan_code.dart';

/// The result of one scan in continuous mode: a line shown under the camera
/// (green when [ok], red otherwise).
class ScanFeedback {
  const ScanFeedback(this.message, {this.ok = true});

  final String message;
  final bool ok;
}

/// Scans one QR code / barcode — with the device camera, or with a handheld
/// USB / Bluetooth scanner (it types the code and presses Enter into the
/// focused box, which also takes a code typed by hand).
///
/// Without [onScan] the dialog closes on the first code and returns it. With
/// [onScan] it stays open (continuous mode, e.g. checking a whole order) and
/// shows the feedback for each code until the user closes it.
Future<ScanCode?> showScanDialog(
  BuildContext context, {
  String title = 'Scan a code',
  String? sub,
  ScanFeedback Function(ScanCode code)? onScan,
}) => showNxDialog<ScanCode>(
  context,
  width: 440,
  builder: (_) => _ScanDialog(title: title, sub: sub, onScan: onScan),
);

class _ScanDialog extends StatefulWidget {
  const _ScanDialog({required this.title, this.sub, this.onScan});

  final String title;
  final String? sub;
  final ScanFeedback Function(ScanCode code)? onScan;

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  final _manual = TextEditingController();
  final _focus = FocusNode();
  MobileScannerController? _camera;
  bool _cameraOn = false;
  ScanFeedback? _last;
  String? _lastRaw;
  DateTime _lastAt = DateTime(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Phones start with the camera; desktops start waiting for a handheld
    // scanner (the camera is one tap away).
    if (_camera == null && !_cameraOn && MediaQuery.sizeOf(context).shortestSide < 600) _startCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    _manual.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCamera() {
    _camera ??= MobileScannerController(formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.code39, BarcodeFormat.upcA]);
    setState(() => _cameraOn = true);
  }

  void _stopCamera() {
    _camera?.dispose();
    _camera = null;
    setState(() => _cameraOn = false);
  }

  /// A camera frame saw [raw]. The camera reports a code several times a
  /// second while it stays in view, so the same code only counts again once
  /// it has been out of view for a moment — holding a label up never adds
  /// more than one. (A handheld scanner or typed code always counts.)
  void _fromCamera(String raw) {
    final text = raw.trim();
    final now = DateTime.now();
    final repeat = text == _lastRaw && now.difference(_lastAt) < const Duration(milliseconds: 1200);
    _lastRaw = text;
    _lastAt = now;
    if (!repeat) _handle(text);
  }

  void _handle(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    final code = ScanCode.parse(text);
    if (widget.onScan == null) {
      Navigator.of(context).pop(code);
      return;
    }
    setState(() => _last = widget.onScan!(code));
    _manual.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxDialogFrame(
      title: widget.title,
      sub: widget.sub ?? 'Point the camera at the label, or scan it with a handheld scanner.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_cameraOn && _camera != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(NxRadius.md),
              child: SizedBox(
                height: 260,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _camera,
                      onDetect: (capture) {
                        final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                        if (raw != null) _fromCamera(raw);
                      },
                      errorBuilder: (context, error) => ColoredBox(
                        color: n.n900,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              error.errorCode == MobileScannerErrorCode.permissionDenied
                                  ? 'Camera permission was refused. Allow the camera for this site, or use a handheld scanner / type the code below.'
                                  : 'No camera available here. Use a handheld scanner or type the code below.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: n.n300, height: 1.4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: n.a300, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(NxRadius.md)),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(PhosphorIconsDuotone.barcode, size: 34, color: n.a300),
                  const SizedBox(height: 8),
                  Text('Ready for a handheld scanner', style: TextStyle(fontSize: 12, color: n.n400)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: NxButton.ghost(
              label: _cameraOn ? 'Stop camera' : 'Use camera',
              icon: _cameraOn ? PhosphorIconsRegular.videoCameraSlash : PhosphorIconsRegular.camera,
              small: true,
              onPressed: _cameraOn ? _stopCamera : _startCamera,
            ),
          ),
          const SizedBox(height: 8),
          NxField(
            label: 'Code',
            hint: 'Handheld scanners type here automatically. A SKU or location code typed by hand works too.',
            child: NxInput(
              controller: _manual,
              focusNode: _focus,
              autofocus: true,
              prefixIcon: PhosphorIconsRegular.qrCode,
              placeholder: 'Scan or type, then Enter',
              onSubmitted: _handle,
            ),
          ),
          if (_last != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('scan-feedback'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (_last!.ok ? n.ok : n.bad).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(NxRadius.md),
              ),
              child: Row(
                children: [
                  Icon(_last!.ok ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.warningCircle, size: 16, color: _last!.ok ? n.ok : n.bad),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_last!.message, style: TextStyle(fontSize: 12.5, color: n.text))),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (widget.onScan == null)
          NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop())
        else
          NxButton.primary(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        if (widget.onScan == null)
          NxButton.primary(label: 'Use code', onPressed: () => _handle(_manual.text)),
      ],
    );
  }
}

/// The small square scan button that sits beside a picker (see [ScanPicker]).
class ScanIconButton extends StatelessWidget {
  const ScanIconButton({super.key, required this.onPressed, this.tooltip = 'Scan a code'});

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => NxIconButton(icon: PhosphorIconsRegular.qrCode, tooltip: tooltip, size: 36, bordered: true, onPressed: onPressed);
}

/// A picker with a scan button on its right: scanning fills the picker.
class ScanPicker extends StatelessWidget {
  const ScanPicker({super.key, required this.child, required this.onScan, this.tooltip = 'Scan a code'});

  final Widget child;
  final VoidCallback? onScan;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: child),
      const SizedBox(width: 6),
      ScanIconButton(onPressed: onScan, tooltip: tooltip),
    ],
  );
}
