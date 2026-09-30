import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../nx/nx_primitives.dart';

/// The "pick an image from device storage" half of an image field that also
/// accepts a pasted URL (see the product-images editor and the workstream
/// form dialog, the two current callers). Holds no picked-file state of its
/// own — the caller keeps the resulting bytes/filename and decides what to
/// do with them (build a preview, submit an upload) — so this stays a
/// small, reusable control rather than a whole image-field widget.
class DeviceImagePicker extends StatefulWidget {
  const DeviceImagePicker({super.key, required this.onPicked, this.label = 'Upload from device', this.enabled = true});

  final void Function(Uint8List bytes, String fileName) onPicked;
  final String label;
  final bool enabled;

  @override
  State<DeviceImagePicker> createState() => _DeviceImagePickerState();
}

class _DeviceImagePickerState extends State<DeviceImagePicker> {
  bool _picking = false;

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
      if (file == null) return; // user cancelled
      final bytes = await file.readAsBytes();
      widget.onPicked(bytes, file.name);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NxButton(
      label: _picking ? 'Choosing…' : widget.label,
      icon: PhosphorIconsRegular.uploadSimple,
      small: true,
      onPressed: (_picking || !widget.enabled) ? null : _pick,
    );
  }
}
