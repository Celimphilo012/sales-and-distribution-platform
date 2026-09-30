import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/leaf_locations_provider.dart';
import '../data/locations_providers.dart';
import '../domain/location.dart';
import '../domain/location_types.dart';

const _custom = '__custom__';
final _digits = [FilteringTextInputFormatter.digitsOnly];

void _refresh(WidgetRef ref, String warehouseId) {
  invalidateWarehouseLocations(ref, warehouseId);
  ref.invalidate(leafLocationsProvider);
}

/// "Name (CODE)" path of [id] within [all], root first.
String locationPath(List<Location> all, String id) {
  final byId = {for (final l in all) l.id: l};
  final out = <String>[];
  for (Location? c = byId[id]; c != null; c = c.parentId == null ? null : byId[c.parentId]) {
    out.insert(0, c.name);
  }
  return out.join(' › ');
}

/// A location type: the suggested labels (narrowed from the parent's type)
/// plus "Custom…", which reveals a free-text box — the type is only a label.
class _TypeField extends StatelessWidget {
  const _TypeField({required this.options, required this.value, required this.custom, required this.onChanged, this.error});

  final List<String> options;
  final String value;
  final TextEditingController custom;
  final ValueChanged<String> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final all = {...options, if (value != _custom && value.isNotEmpty) value}.toList();
    return NxField(
      label: 'Type',
      required: true,
      error: error,
      hint: 'Suggested from the parent’s type — a free label, not a constraint',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxSelect<String>(
            options: [for (final t in all) NxOption(t, t), const NxOption(_custom, 'Custom…')],
            value: value,
            onChanged: (v) => onChanged(v ?? all.first),
          ),
          if (value == _custom) ...[
            const SizedBox(height: 6),
            NxInput(controller: custom, placeholder: 'e.g. COLD ROOM', error: error != null, autofocus: true),
          ],
        ],
      ),
    );
  }
}

// ─── Add / edit ─────────────────────────────────────────────────────────────

/// Add a root location ([warehouseId]), a child ([parent]) or edit
/// ([location]) — the prototype's location form, plus capacity.
Future<void> showLocationForm(BuildContext context, {required String warehouseId, Location? parent, Location? location, List<Location> all = const []}) =>
    showNxDialog<void>(
      context,
      builder: (_) => _LocationForm(warehouseId: warehouseId, parent: parent, location: location, all: all),
    );

class _LocationForm extends ConsumerStatefulWidget {
  const _LocationForm({required this.warehouseId, this.parent, this.location, required this.all});

  final String warehouseId;
  final Location? parent;
  final Location? location;
  final List<Location> all;

  @override
  ConsumerState<_LocationForm> createState() => _LocationFormState();
}

class _LocationFormState extends ConsumerState<_LocationForm> {
  late final _name = TextEditingController(text: widget.location?.name ?? '');
  late final _code = TextEditingController(text: widget.location?.code ?? '');
  late final _desc = TextEditingController(text: widget.location?.description ?? '');
  late final _capacity = TextEditingController(text: widget.location?.capacity?.toString() ?? '');
  final _customType = TextEditingController();
  late final List<String> _types = widget.location != null
      ? kSuggestedLocationTypes
      : suggestedChildLocationTypes(widget.parent?.locationType);
  late String _type = widget.location?.locationType ?? _types.first;
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  bool get _editing => widget.location != null;

  @override
  void dispose() {
    for (final c in [_name, _code, _desc, _capacity, _customType]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final type = (_type == _custom ? _customType.text : _type).trim().toUpperCase();
    final code = _code.text.trim().toUpperCase();
    final capText = _capacity.text.trim();
    final capacity = capText.isEmpty ? null : int.tryParse(capText);
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Required',
      if (!_editing && code.isEmpty) 'code': 'Required',
      if (type.isEmpty) 'type': 'Required',
      if (capText.isNotEmpty && capacity == null) 'cap': 'Whole units only',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    final api = ref.read(locationsApiProvider);
    final desc = _desc.text.trim();
    try {
      if (_editing) {
        await api.update(
          widget.location!.id,
          name: _name.text.trim(),
          locationType: type,
          description: desc,
          capacity: capacity,
          clearCapacity: capacity == null && widget.location!.capacity != null,
        );
      } else if (widget.parent != null) {
        await api.addChild(widget.parent!.id, name: _name.text.trim(), code: code, locationType: type, description: desc, capacity: capacity);
      } else {
        await api.createRoot(widget.warehouseId, name: _name.text.trim(), code: code, locationType: type, description: desc, capacity: capacity);
      }
      _refresh(ref, widget.warehouseId);
      if (mounted) Navigator.of(context).pop();
      NxToast.ok(_editing ? 'Location updated' : 'Location added', '${_name.text.trim()} (${_editing ? widget.location!.code : code})');
    } on AppError catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final parent = widget.parent;
    return NxDialogFrame(
      title: _editing ? 'Edit location' : (parent != null ? 'Add child location' : 'Add root location'),
      sub: parent != null
          ? 'Under ${locationPath(widget.all, parent.id)}'
          : _editing
          ? locationPath(widget.all, widget.location!.id)
          : 'A top-level area of this warehouse',
      body: NxFormGrid(
        children: [
          NxField(
            label: 'Name',
            required: true,
            error: _errors['name'],
            child: NxInput(controller: _name, placeholder: 'Rack 04', error: _errors['name'] != null, autofocus: true),
          ),
          NxField(
            label: 'Code',
            required: true,
            error: _errors['code'],
            hint: _editing ? 'Codes are fixed once created' : null,
            child: NxInput(
              controller: _code,
              placeholder: parent != null ? '${parent.code}-04' : 'D',
              enabled: !_editing,
              error: _errors['code'] != null,
            ),
          ),
          _TypeField(
            options: _types,
            value: _type,
            custom: _customType,
            error: _errors['type'],
            onChanged: (v) => setState(() => _type = v),
          ),
          NxField(
            label: 'Capacity (units)',
            error: _errors['cap'],
            hint: 'For fill and utilisation — usually set on storage slots',
            child: NxInput(controller: _capacity, placeholder: 'Optional', inputFormatters: _digits, error: _errors['cap'] != null),
          ),
          NxSpan2(
            child: NxField(label: 'Description', child: NxInput(controller: _desc, maxLines: 3, minLines: 2)),
          ),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Add location'), onPressed: _saving ? null : _submit),
      ],
    );
  }
}

// ─── Create levels ──────────────────────────────────────────────────────────

/// Adds N numbered child locations under [parent] (the prototype's "Create
/// levels"), optionally all with the same capacity.
Future<void> showCreateLevels(BuildContext context, {required Location parent, required List<Location> all}) =>
    showNxDialog<void>(context, builder: (_) => _LevelsForm(parent: parent, all: all));

class _LevelsForm extends ConsumerStatefulWidget {
  const _LevelsForm({required this.parent, required this.all});

  final Location parent;
  final List<Location> all;

  @override
  ConsumerState<_LevelsForm> createState() => _LevelsFormState();
}

class _LevelsFormState extends ConsumerState<_LevelsForm> {
  late final List<String> _types = suggestedChildLocationTypes(widget.parent.locationType);
  late String _type = _types.contains('LEVEL') ? 'LEVEL' : _types.first;
  final _customType = TextEditingController();
  final _count = TextEditingController(text: '4');
  final _prefix = TextEditingController(text: 'Level');
  final _codePrefix = TextEditingController();
  late final _start = TextEditingController(text: '${widget.all.where((l) => l.parentId == widget.parent.id).length + 1}');
  final _capacity = TextEditingController();
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    for (final c in [_customType, _count, _prefix, _codePrefix, _start, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final count = int.tryParse(_count.text.trim());
    final start = int.tryParse(_start.text.trim());
    final capText = _capacity.text.trim();
    final capacity = capText.isEmpty ? null : int.tryParse(capText);
    final type = (_type == _custom ? _customType.text : _type).trim().toUpperCase();
    final errors = <String, String>{
      if (count == null || count < 1) 'count': 'At least 1',
      if (start == null || start < 1) 'start': 'At least 1',
      if (_prefix.text.trim().isEmpty) 'prefix': 'Required',
      if (type.isEmpty) 'type': 'Required',
      if (capText.isNotEmpty && capacity == null) 'cap': 'Whole units only',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final made = await ref.read(locationsApiProvider).generateLevels(
        widget.parent.id,
        count: count!,
        locationType: type,
        namePrefix: _prefix.text.trim(),
        codePrefix: _codePrefix.text.trim().isEmpty ? null : _codePrefix.text.trim().toUpperCase(),
        startIndex: start,
        capacity: capacity,
      );
      _refresh(ref, widget.parent.warehouseId);
      if (mounted) Navigator.of(context).pop();
      NxToast.ok(
        'Created ${made.length} ${type.toLowerCase()}${made.length == 1 ? '' : 's'}',
        made.isEmpty ? null : '${made.first.code}${made.length > 1 ? ' → ${made.last.code}' : ''}',
      );
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxDialogFrame(
      title: 'Create levels',
      sub: 'Adds numbered child locations under ${widget.parent.name} (${widget.parent.code}).',
      body: NxFormGrid(
        children: [
          NxField(
            label: 'How many',
            required: true,
            error: _errors['count'],
            child: NxInput(controller: _count, inputFormatters: _digits, error: _errors['count'] != null, autofocus: true),
          ),
          _TypeField(
            options: _types,
            value: _type,
            custom: _customType,
            error: _errors['type'],
            onChanged: (v) => setState(() => _type = v),
          ),
          NxField(
            label: 'Name prefix',
            required: true,
            error: _errors['prefix'],
            child: NxInput(controller: _prefix, error: _errors['prefix'] != null),
          ),
          NxField(
            label: 'Start at',
            required: true,
            error: _errors['start'],
            child: NxInput(controller: _start, inputFormatters: _digits, error: _errors['start'] != null),
          ),
          NxField(
            label: 'Code prefix',
            hint: 'Default: ${widget.parent.code}-<first letter of the type>',
            child: NxInput(controller: _codePrefix, placeholder: 'Optional'),
          ),
          NxField(
            label: 'Capacity each (units)',
            error: _errors['cap'],
            child: NxInput(controller: _capacity, placeholder: 'Optional', inputFormatters: _digits, error: _errors['cap'] != null),
          ),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Creating…' : 'Create levels', onPressed: _saving ? null : _submit),
      ],
    );
  }
}

// ─── Move ───────────────────────────────────────────────────────────────────

/// Re-parents [location] (and everything under it — stock moves with it).
Future<void> showMoveLocation(BuildContext context, {required Location location, required List<Location> all}) =>
    showNxDialog<void>(context, builder: (_) => _MoveForm(location: location, all: all));

class _MoveForm extends ConsumerStatefulWidget {
  const _MoveForm({required this.location, required this.all});

  final Location location;
  final List<Location> all;

  @override
  ConsumerState<_MoveForm> createState() => _MoveFormState();
}

class _MoveFormState extends ConsumerState<_MoveForm> {
  late String _parent = widget.location.parentId ?? '';
  bool _saving = false;
  String? _formError;

  Set<String> get _blocked {
    final out = {widget.location.id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final l in widget.all) {
        if (l.parentId != null && out.contains(l.parentId) && out.add(l.id)) grew = true;
      }
    }
    return out;
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final target = _parent.isEmpty ? null : _parent;
      await ref.read(locationsApiProvider).move(widget.location.id, newParentId: target);
      _refresh(ref, widget.location.warehouseId);
      if (mounted) Navigator.of(context).pop();
      final code = widget.all.where((l) => l.id == target).firstOrNull?.code;
      NxToast.ok('Location moved', '${widget.location.code} → ${code ?? 'top level'}');
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final blocked = _blocked;
    final options = [
      const NxOption<String>('', '— Top level'),
      for (final l in widget.all.where((l) => !blocked.contains(l.id) && l.isActive))
        NxOption(l.id, '${l.name} (${l.code})', sub: locationPath(widget.all, l.id), search: l.locationType),
    ];
    return NxDialogFrame(
      title: 'Move location',
      sub: 'Moves ${widget.location.name} (${widget.location.code}) and everything under it. Stock moves with it.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxField(
            label: 'New parent',
            child: NxSelect<String>(
              options: options,
              value: _parent,
              searchable: true,
              searchPlaceholder: 'Search by name or code',
              onChanged: (v) => setState(() => _parent = v ?? ''),
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 10),
            Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad)),
          ],
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(
          label: _saving ? 'Moving…' : 'Move',
          onPressed: _saving || _parent == (widget.location.parentId ?? '') ? null : _submit,
        ),
      ],
    );
  }
}
