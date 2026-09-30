import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../../shared/widgets/device_image_picker.dart';
import '../../users/data/users_providers.dart';
import '../../users/domain/user.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../data/workstream_managers_providers.dart';
import '../data/workstreams_providers.dart';
import '../domain/workstream.dart';
import 'widgets/workstream_image_view.dart';

/// New / edit workstream (the prototype's workstream form, 560px): name,
/// code, warehouse, description, scoped managers, contact, status — plus the
/// app's image (URL or, once created, an upload from the device).
Future<void> showWorkstreamFormDialog(BuildContext context, {Workstream? workstream, String? initialWarehouseId}) =>
    showNxDialog<void>(
      context,
      width: 560,
      builder: (_) => _WorkstreamForm(workstream: workstream, initialWarehouseId: initialWarehouseId),
    );

class _WorkstreamForm extends ConsumerStatefulWidget {
  const _WorkstreamForm({this.workstream, this.initialWarehouseId});

  final Workstream? workstream;
  final String? initialWarehouseId;

  @override
  ConsumerState<_WorkstreamForm> createState() => _WorkstreamFormState();
}

class _WorkstreamFormState extends ConsumerState<_WorkstreamForm> {
  late final _name = TextEditingController(text: widget.workstream?.name ?? '');
  late final _code = TextEditingController(text: widget.workstream?.code ?? '');
  late final _desc = TextEditingController(text: widget.workstream?.description ?? '');
  late final _imageUrl = TextEditingController(text: widget.workstream?.imageUrl ?? '');
  late final _contactName = TextEditingController(text: widget.workstream?.contactName ?? '');
  late final _contactEmail = TextEditingController(text: widget.workstream?.contactEmail ?? '');
  late final _contactPhone = TextEditingController(text: widget.workstream?.contactPhone ?? '');
  late String? _warehouseId = widget.workstream?.warehouseId ?? widget.initialWarehouseId;
  late bool _active = widget.workstream?.isActive ?? true;
  late Set<String> _managers = {...?widget.workstream?.managers.map((m) => m.userId)};
  late Workstream? _live = widget.workstream;
  final Map<String, String> _errors = {};
  bool _saving = false;
  bool _uploading = false;
  String? _formError;

  bool get _editing => widget.workstream != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _desc, _imageUrl, _contactName, _contactEmail, _contactPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit({required bool canAssign}) async {
    final email = _contactEmail.text.trim();
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Required',
      if (_code.text.trim().isEmpty) 'code': 'Required',
      if (_warehouseId == null) 'wh': 'Choose a warehouse',
      if (email.isNotEmpty && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) 'email': 'Enter a valid email',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    final api = ref.read(workstreamsApiProvider);
    final code = _code.text.trim().toUpperCase();
    try {
      final Workstream saved;
      if (_editing) {
        final ws = widget.workstream!;
        saved = await api.update(
          ws.id,
          name: _name.text.trim(),
          code: code,
          description: _opt(_desc),
          imageUrl: _opt(_imageUrl),
          contactName: _opt(_contactName),
          contactEmail: _opt(_contactEmail),
          contactPhone: _opt(_contactPhone),
          isActive: _active && !ws.isActive ? true : null,
        );
        if (!_active && ws.isActive) await api.deactivate(ws.id);
      } else {
        saved = await api.create(
          warehouseId: _warehouseId!,
          name: _name.text.trim(),
          code: code,
          description: _opt(_desc),
          imageUrl: _opt(_imageUrl),
          contactName: _opt(_contactName),
          contactEmail: _opt(_contactEmail),
          contactPhone: _opt(_contactPhone),
        );
        if (!_active) await api.deactivate(saved.id);
      }
      if (canAssign) {
        final before = {...?widget.workstream?.managers.map((m) => m.userId)};
        final managers = ref.read(workstreamManagersApiProvider);
        for (final id in _managers.difference(before)) {
          await managers.assign(saved.id, id);
        }
        for (final id in before.difference(_managers)) {
          await managers.unassign(saved.id, id);
        }
        ref.invalidate(workstreamManagersProvider(saved.id));
      }
      invalidateWorkstreams(ref);
      if (mounted) Navigator.of(context).pop();
      NxToast.ok(_editing ? 'Workstream updated' : 'Workstream created', '${_name.text.trim()} ($code)');
    } on AppError catch (e) {
      invalidateWorkstreams(ref);
      setState(() {
        if (e.message.toLowerCase().contains('code')) {
          _errors['code'] = e.message;
        } else {
          _formError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upload(Uint8List bytes, String fileName) async {
    setState(() => _uploading = true);
    try {
      final updated = await ref.read(workstreamsApiProvider).uploadImage(widget.workstream!.id, bytes: bytes, fileName: fileName);
      _imageUrl.clear();
      setState(() => _live = updated);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeImage() async {
    setState(() => _uploading = true);
    try {
      final updated = await ref.read(workstreamsApiProvider).removeImage(widget.workstream!.id);
      _imageUrl.clear();
      setState(() => _live = updated);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canAssign = (user?.can('workstreams.assign') ?? false) && (user?.can('users.manage') ?? false);
    final warehouses = ref.watch(warehousesProvider(false)).value ?? const [];
    final users = canAssign ? ref.watch(usersListProvider).value ?? const <WarehouseUser>[] : const <WarehouseUser>[];
    final candidates = users.where((u) => u.status == UserStatus.active || _managers.contains(u.id)).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final live = _live;

    return NxDialogFrame(
      title: _editing ? 'Edit workstream' : 'New workstream',
      sub: 'Organises the catalogue: Warehouse → Workstream → Category → Product. Never affects stock.',
      body: NxFormGrid(
        children: [
          NxField(
            label: 'Name',
            required: true,
            error: _errors['name'],
            child: NxInput(controller: _name, error: _errors['name'] != null, autofocus: !_editing),
          ),
          NxField(
            label: 'Code',
            required: true,
            error: _errors['code'],
            child: NxInput(controller: _code, placeholder: 'GRC', error: _errors['code'] != null),
          ),
          NxSpan2(
            child: NxField(
              label: 'Warehouse',
              required: true,
              error: _errors['wh'],
              hint: _editing ? 'A workstream stays in the warehouse it was created in' : null,
              child: NxSelect<String>(
                options: [for (final w in warehouses) NxOption(w.id, '${w.name} (${w.code})')],
                value: _warehouseId,
                enabled: !_editing,
                error: _errors['wh'] != null,
                placeholder: 'Choose a warehouse',
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
            ),
          ),
          NxSpan2(
            child: NxField(label: 'Description', child: NxInput(controller: _desc, maxLines: 3, minLines: 2)),
          ),
          if (canAssign)
            NxSpan2(
              child: NxField(
                label: 'Managers',
                hint: 'Scoped managers only see this workstream’s catalogue',
                child: candidates.isEmpty
                    ? Text('No active users', style: TextStyle(fontSize: 12, color: n.n500))
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final u in candidates)
                            NxChipToggle(
                              label: u.fullName,
                              selected: _managers.contains(u.id),
                              showCheck: true,
                              onTap: () => setState(() {
                                _managers = {..._managers};
                                _managers.contains(u.id) ? _managers.remove(u.id) : _managers.add(u.id);
                              }),
                            ),
                        ],
                      ),
              ),
            ),
          NxField(label: 'Contact name', child: NxInput(controller: _contactName)),
          NxField(
            label: 'Contact email',
            error: _errors['email'],
            child: NxInput(controller: _contactEmail, placeholder: 'name@example.com', error: _errors['email'] != null),
          ),
          NxField(label: 'Contact phone', child: NxInput(controller: _contactPhone, placeholder: '+268 7612 3456')),
          NxField(
            label: 'Status',
            child: Align(
              alignment: Alignment.centerLeft,
              child: NxSeg<bool>(
                options: const [(true, 'Active', null), (false, 'Inactive', null)],
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ),
          ),
          NxSpan2(
            child: NxField(
              label: 'Image',
              hint: _editing ? 'Paste a link, or upload a file from this device' : 'Paste a link — uploading works once the workstream exists',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (live != null && live.hasImage) ...[
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(NxRadius.md),
                          child: SizedBox(width: 72, height: 48, child: WorkstreamImageView(workstream: live)),
                        ),
                        const SizedBox(width: 10),
                        NxButton.ghost(
                          label: 'Remove image',
                          icon: PhosphorIconsRegular.trash,
                          small: true,
                          color: n.bad,
                          onPressed: _uploading ? null : _removeImage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(child: NxInput(controller: _imageUrl, placeholder: 'https://…')),
                      if (_editing) ...[
                        const SizedBox(width: 8),
                        DeviceImagePicker(enabled: !_uploading, onPicked: _upload, label: _uploading ? 'Uploading…' : 'Upload'),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_formError != null)
            NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(
          label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Create workstream'),
          onPressed: _saving ? null : () => _submit(canAssign: canAssign),
        ),
      ],
    );
  }
}
