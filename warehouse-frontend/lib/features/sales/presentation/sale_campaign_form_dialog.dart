import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_options.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/sales_api.dart';
import '../data/sales_providers.dart';
import '../domain/sale_campaign.dart';

enum _FormMode { create, edit, reopen }

/// Schedule a new sale campaign. Never live on save — a different user must approve it (see
/// sale_campaign_review_dialog.dart).
Future<void> showSaleCampaignForm(BuildContext context) =>
    showNxDialog<void>(context, width: 680, builder: (_) => const _CampaignForm(mode: _FormMode.create));

/// Free edit of your own still-PENDING_APPROVAL campaign — same form, prefilled, no new approval
/// needed since nothing's been decided yet.
Future<void> showSaleCampaignEditForm(BuildContext context, SaleCampaign campaign) =>
    showNxDialog<void>(context, width: 680, builder: (_) => _CampaignForm(mode: _FormMode.edit, existing: campaign));

/// Brings a decided (SCHEDULED/ACTIVE/ENDED/REJECTED/CANCELLED) campaign back to PENDING_APPROVAL —
/// optionally with new terms at the same time. Always needs a fresh approval by a different user.
Future<void> showSaleCampaignReopenForm(BuildContext context, SaleCampaign campaign) =>
    showNxDialog<void>(context, width: 680, builder: (_) => _CampaignForm(mode: _FormMode.reopen, existing: campaign));

class _ProductRow {
  _ProductRow();

  String? productId;
  SaleDiscountType discountType = SaleDiscountType.percent;
  final discountValue = TextEditingController();
  final minQuantity = TextEditingController(text: '1');

  factory _ProductRow.fromExisting(SaleCampaignProduct p) => _ProductRow()
    ..productId = p.productId
    ..discountType = p.discountType
    ..discountValue.text = fmtNum(p.discountValue)
    ..minQuantity.text = fmtNum(p.minQuantity);

  void dispose() {
    discountValue.dispose();
    minQuantity.dispose();
  }
}

class _CampaignForm extends ConsumerStatefulWidget {
  const _CampaignForm({required this.mode, this.existing});

  final _FormMode mode;
  final SaleCampaign? existing;

  @override
  ConsumerState<_CampaignForm> createState() => _CampaignFormState();
}

class _CampaignFormState extends ConsumerState<_CampaignForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _maxUsesPerCustomer = TextEditingController();
  DateTime? _startsAt;
  DateTime? _endsAt;
  SaleEligibility _eligibility = SaleEligibility.allCustomers;
  bool _hasDailyWindow = false;
  DateTime? _dailyWindowStart;
  DateTime? _dailyWindowEnd;
  late final List<_ProductRow> _rows;
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing.name;
      _description.text = existing.description ?? '';
      _startsAt = existing.startsAt.toLocal();
      _endsAt = existing.endsAt.toLocal();
      _eligibility = existing.eligibility;
      _maxUsesPerCustomer.text = existing.maxUsesPerCustomer == null ? '' : '${existing.maxUsesPerCustomer}';
      _hasDailyWindow = existing.isDailyWindow;
      _dailyWindowStart = existing.dailyWindowStartLocal;
      _dailyWindowEnd = existing.dailyWindowEndLocal;
      _rows = existing.products.isEmpty ? [_ProductRow()] : existing.products.map(_ProductRow.fromExisting).toList();
    } else {
      _rows = [_ProductRow()];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _maxUsesPerCustomer.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial ?? now));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<DateTime?> _pickTime(DateTime? initial) async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial ?? DateTime.now()));
    if (time == null || !mounted) return null;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day, time.hour, time.minute);
  }

  Future<void> _submit(List<Product> products) async {
    final errors = <String, String>{};
    if (_name.text.trim().isEmpty) errors['name'] = 'Required';
    if (_startsAt == null) errors['starts'] = 'Required';
    if (_endsAt == null) errors['ends'] = 'Required';
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) errors['ends'] = 'Must be after the start';
    if (_hasDailyWindow && (_dailyWindowStart == null || _dailyWindowEnd == null)) {
      errors['window'] = 'Choose both a start and an end time';
    } else if (_hasDailyWindow && !_dailyWindowEnd!.isAfter(_dailyWindowStart!)) {
      errors['window'] = 'End time must be after the start time';
    }
    int? maxUsesPerCustomer;
    final maxUsesText = _maxUsesPerCustomer.text.trim();
    if (maxUsesText.isNotEmpty) {
      maxUsesPerCustomer = int.tryParse(maxUsesText);
      if (maxUsesPerCustomer == null || maxUsesPerCustomer <= 0) {
        errors['maxUses'] = 'Enter a whole number above 0, or leave it blank for unlimited';
      }
    }

    final inputs = <SaleCampaignProductInput>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      if (r.productId == null) {
        errors['row$i'] = 'Choose a product';
        continue;
      }
      final value = double.tryParse(r.discountValue.text.trim());
      if (value == null || value <= 0) {
        errors['row$i'] = 'Enter a discount above 0';
        continue;
      }
      final minQty = double.tryParse(r.minQuantity.text.trim());
      if (minQty == null || minQty <= 0) {
        errors['row$i'] = 'Enter a minimum quantity above 0';
        continue;
      }
      inputs.add(SaleCampaignProductInput(productId: r.productId!, discountType: r.discountType, discountValue: value, minQuantity: minQty));
    }
    final seen = <String>{};
    for (final p in inputs) {
      if (!seen.add(p.productId)) errors['dup'] = 'The same product is on this campaign twice';
    }

    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(salesApiProvider);
      final terms = SaleCampaignTerms(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        startsAt: _startsAt!,
        endsAt: _endsAt!,
        eligibility: _eligibility,
        dailyWindowStart: _hasDailyWindow ? _dailyWindowStart : null,
        dailyWindowEnd: _hasDailyWindow ? _dailyWindowEnd : null,
        maxUsesPerCustomer: maxUsesPerCustomer,
        products: inputs,
      );
      switch (widget.mode) {
        case _FormMode.create:
          await api.create(terms);
        case _FormMode.edit:
          await api.editPending(widget.existing!.id, terms);
        case _FormMode.reopen:
          await api.reopen(widget.existing!.id, terms: terms);
      }
      ref.invalidate(salesListProvider);
      if (widget.existing != null) ref.invalidate(saleCampaignProvider(widget.existing!.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      final name = _name.text.trim();
      switch (widget.mode) {
        case _FormMode.create:
          NxToast.ok('Sale campaign scheduled', '$name — awaiting approval before it goes live.');
        case _FormMode.edit:
          NxToast.ok('Sale campaign updated', name);
        case _FormMode.reopen:
          NxToast.ok('Sale campaign reopened', '$name — awaiting a fresh approval before it goes live.');
      }
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final products = ref.watch(productsListProvider).value ?? const <Product>[];
    final options = productOptions(products);
    final pullsOffSaleNow = widget.mode != _FormMode.create && widget.existing?.status == SaleCampaignStatus.active;

    Widget dateField(String label, DateTime? value, String errorKey, void Function(DateTime) onPicked) => NxField(
      label: label,
      required: true,
      error: _errors[errorKey],
      child: NxButton(
        label: value == null ? 'Choose date & time' : fmtDateTime(value),
        icon: PhosphorIconsRegular.calendar,
        onPressed: () async {
          final picked = await _pickDateTime(value);
          if (picked != null) setState(() => onPicked(picked));
        },
      ),
    );

    Widget timeField(String label, DateTime? value, void Function(DateTime) onPicked) => NxField(
      label: label,
      child: NxButton(
        label: value == null ? 'Choose time' : fmtTime(value),
        icon: PhosphorIconsRegular.clock,
        onPressed: () async {
          final picked = await _pickTime(value);
          if (picked != null) setState(() => onPicked(picked));
        },
      ),
    );

    final (title, sub, actionLabel, savingLabel) = switch (widget.mode) {
      _FormMode.create => ('Schedule a sale campaign', 'Nothing goes live until a different user approves it.', 'Schedule campaign', 'Scheduling…'),
      _FormMode.edit => ('Edit campaign', 'Still pending approval — change anything before it\'s reviewed.', 'Save changes', 'Saving…'),
      _FormMode.reopen => (
          'Reopen campaign',
          'This needs a fresh approval from a different user before it\'s live again.',
          'Reopen',
          'Reopening…',
        ),
    };

    return NxDialogFrame(
      title: title,
      sub: sub,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pullsOffSaleNow) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: n.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(NxRadius.md)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIconsRegular.warning, size: 18, color: n.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "This campaign is currently live. Saving pulls its product(s) off sale immediately, until it's approved again.",
                      style: TextStyle(fontSize: 12, color: n.text),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          NxFormGrid(
            children: [
              NxSpan2(
                child: NxField(
                  label: 'Name',
                  required: true,
                  error: _errors['name'],
                  child: NxInput(controller: _name, placeholder: 'e.g. Black Friday', error: _errors['name'] != null),
                ),
              ),
              dateField('Starts', _startsAt, 'starts', (d) => _startsAt = d),
              dateField('Ends', _endsAt, 'ends', (d) => _endsAt = d),
              NxField(
                label: 'Who can buy at this price',
                child: NxSelect<SaleEligibility>(
                  options: [for (final e in SaleEligibility.values) NxOption(e, e.label)],
                  value: _eligibility,
                  onChanged: (v) => setState(() => _eligibility = v ?? _eligibility),
                ),
              ),
              NxField(
                label: 'Limit per customer (optional)',
                error: _errors['maxUses'],
                child: NxInput(
                  controller: _maxUsesPerCustomer,
                  placeholder: 'Unlimited',
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  error: _errors['maxUses'] != null,
                ),
              ),
              NxSpan2(
                child: NxField(label: 'Description (optional)', child: NxInput(controller: _description, maxLines: 3, minLines: 2)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NxCheckToggle(
            label: 'Limit to a daily time window',
            value: _hasDailyWindow,
            onChanged: (v) => setState(() => _hasDailyWindow = v),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              'Only live at this time of day, every day, between the start and end dates above.',
              style: TextStyle(fontSize: 11, color: n.n500),
            ),
          ),
          if (_hasDailyWindow) ...[
            const SizedBox(height: 8),
            NxFormGrid(
              children: [
                timeField('Window starts', _dailyWindowStart, (d) => _dailyWindowStart = d),
                timeField('Window ends', _dailyWindowEnd, (d) => _dailyWindowEnd = d),
              ],
            ),
            if (_errors['window'] != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['window']!, style: TextStyle(fontSize: 11, color: n.bad))),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text('Products on this campaign', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text))),
              NxButton(
                label: 'Add product',
                small: true,
                icon: PhosphorIconsRegular.plus,
                onPressed: () => setState(() => _rows.add(_ProductRow())),
              ),
            ],
          ),
          if (_errors['dup'] != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['dup']!, style: TextStyle(fontSize: 11, color: n.bad))),
          const SizedBox(height: 8),
          for (var i = 0; i < _rows.length; i++) _ProductRowEditor(
            key: ValueKey(_rows[i]),
            row: _rows[i],
            options: options,
            products: products,
            error: _errors['row$i'],
            onRemove: _rows.length > 1 ? () => setState(() { _rows[i].dispose(); _rows.removeAt(i); }) : null,
            onChanged: () => setState(() {}),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 10),
            Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad)),
          ],
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: _saving ? null : () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? savingLabel : actionLabel, onPressed: _saving ? null : () => _submit(products)),
      ],
    );
  }
}

class _ProductRowEditor extends StatelessWidget {
  const _ProductRowEditor({
    super.key,
    required this.row,
    required this.options,
    required this.products,
    required this.error,
    required this.onRemove,
    required this.onChanged,
  });

  final _ProductRow row;
  final List<NxOption<String>> options;
  final List<Product> products;
  final String? error;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final product = products.where((p) => p.id == row.productId).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: n.surface, borderRadius: BorderRadius.circular(NxRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NxField(
                  label: 'Product',
                  error: error,
                  child: NxSelect<String>(
                    options: options,
                    value: row.productId,
                    searchable: true,
                    searchPlaceholder: 'Search by SKU or name',
                    placeholder: 'Choose a product',
                    error: error != null,
                    onChanged: (v) {
                      row.productId = v;
                      onChanged();
                    },
                  ),
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: NxIconButton(icon: PhosphorIconsRegular.x, tooltip: 'Remove', size: 32, onPressed: onRemove),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: NxField(
                  label: 'Discount',
                  child: NxSelect<SaleDiscountType>(
                    options: [for (final t in SaleDiscountType.values) NxOption(t, t.label)],
                    value: row.discountType,
                    onChanged: (v) {
                      row.discountType = v ?? row.discountType;
                      onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NxField(
                  label: row.discountType == SaleDiscountType.percent
                      ? '% off'
                      : row.discountType == SaleDiscountType.fixedAmount
                          ? 'Amount off'
                          : 'Sale price',
                  child: NxInput(controller: row.discountValue, inputFormatters: NxInput.decimals(2), onChanged: (_) => onChanged()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NxField(
                  label: 'Minimum qty',
                  child: NxInput(controller: row.minQuantity, inputFormatters: NxInput.decimals(3)),
                ),
              ),
            ],
          ),
          if (product != null && row.discountValue.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Normally ${fmtMoney(product.sellingPrice)} → ${fmtMoney(_preview(product, row))}',
              style: TextStyle(fontSize: 11, color: n.n500),
            ),
          ],
        ],
      ),
    );
  }

  double _preview(Product product, _ProductRow row) {
    final value = double.tryParse(row.discountValue.text.trim()) ?? 0;
    final raw = switch (row.discountType) {
      SaleDiscountType.percent => product.sellingPrice * (1 - value / 100),
      SaleDiscountType.fixedAmount => product.sellingPrice - value,
      SaleDiscountType.fixedPrice => value,
    };
    return raw < 0 ? 0 : (raw * 100).round() / 100;
  }
}
