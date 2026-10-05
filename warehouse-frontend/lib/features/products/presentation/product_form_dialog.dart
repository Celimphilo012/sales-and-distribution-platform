import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../../shared/widgets/device_image_picker.dart';
import '../../attribute_types/data/attribute_types_providers.dart';
import '../../attribute_types/domain/attribute_type.dart';
import '../../categories/data/categories_providers.dart';
import '../../categories/domain/category.dart';
import '../../receiving/presentation/receive_sheet.dart';
import '../data/products_providers.dart';
import '../domain/product.dart';
import '../domain/product_attribute.dart';
import '../domain/tracking_mode.dart';
import 'products_list_providers.dart';
import 'widgets/product_image_view.dart';

/// Units of measure offered by default (any unit already on a product is
/// offered too, so an existing value is never lost).
const kDefaultUoms = ['each', 'bag', 'bar', 'bottle', 'box', 'case', 'jar', 'kg', 'litre', 'pack', 'roll', 'tin'];

/// New / edit product (the prototype's product form, 560px, two columns).
/// Stock never changes here — it arrives through receiving. Keeps what the
/// app already did beyond the prototype: one field per active ATTRIBUTE TYPE
/// (number types validated) and, when editing, the product's IMAGES.
Future<void> showProductForm(BuildContext context, {Product? product}) =>
    showNxDialog<void>(context, width: 560, builder: (_) => _ProductForm(product: product));

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.product});

  final Product? product;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _min = TextEditingController(text: _num(widget.product?.minStockLevel ?? 10));
  late final _price = TextEditingController(text: widget.product == null ? '' : _num(widget.product!.sellingPrice));
  late final _cost = TextEditingController(text: widget.product?.costPrice == null ? '' : _num(widget.product!.costPrice!));
  late final _desc = TextEditingController(text: widget.product?.description ?? '');
  late String? _categoryId = widget.product?.categoryId;
  late String _uom = widget.product?.uom ?? 'each';
  late TrackingMode _trackingMode = widget.product?.trackingMode ?? TrackingMode.bulk;
  final Map<String, TextEditingController> _attr = {};
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  bool get _editing => widget.product != null;

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in [_sku, _name, _min, _price, _cost, _desc, ..._attr.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _attrController(AttributeType t) => _attr.putIfAbsent(t.id, () {
    final existing = widget.product?.attributes.where((a) => a.attributeTypeId == t.id).firstOrNull;
    return TextEditingController(text: existing?.value ?? '');
  });

  Future<void> _submit(List<AttributeType> types) async {
    final errors = <String, String>{};
    final price = double.tryParse(_price.text.trim());
    final cost = _cost.text.trim().isEmpty ? null : double.tryParse(_cost.text.trim());
    final min = double.tryParse(_min.text.trim());
    if (_sku.text.trim().isEmpty) errors['sku'] = 'Required';
    if (_name.text.trim().isEmpty) errors['name'] = 'Required';
    if (_categoryId == null) errors['category'] = 'Choose a category';
    if (price == null || price <= 0) errors['price'] = 'Must be greater than 0';
    if (_cost.text.trim().isNotEmpty && (cost == null || cost < 0)) errors['cost'] = 'Enter a valid amount';
    if (min == null || min < 0) errors['min'] = 'Enter 0 or more';
    final attributes = <ProductAttributeInput>[];
    for (final t in types) {
      final v = _attrController(t).text.trim();
      if (v.isEmpty) continue;
      if (t.dataType == AttributeDataType.number) {
        final n = num.tryParse(v);
        if (n == null) {
          errors['attr:${t.id}'] = 'Must be a number';
          continue;
        }
        attributes.add(ProductAttributeInput(attributeTypeId: t.id, value: n));
      } else {
        attributes.add(ProductAttributeInput(attributeTypeId: t.id, value: v));
      }
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
      final api = ref.read(productsApiProvider);
      final desc = _desc.text.trim();
      if (_editing) {
        await api.update(
          widget.product!.id,
          sku: _sku.text.trim() == widget.product!.sku ? null : _sku.text.trim(),
          name: _name.text.trim(),
          description: desc.isEmpty ? null : desc,
          categoryId: _categoryId!,
          sellingPrice: price!,
          costPrice: cost,
          uom: _uom,
          minStockLevel: min!,
          attributes: attributes,
        );
        invalidateProduct(ref, widget.product!.id);
        if (mounted) Navigator.of(context).pop();
        NxToast.ok('Product updated', '${widget.product!.sku} · ${_name.text.trim()}');
      } else {
        final created = await api.create(
          sku: _sku.text.trim(),
          name: _name.text.trim(),
          description: desc.isEmpty ? null : desc,
          categoryId: _categoryId!,
          sellingPrice: price!,
          costPrice: cost,
          uom: _uom,
          minStockLevel: min,
          trackingMode: _trackingMode,
          attributes: attributes,
        );
        ref.invalidate(productsListProvider);
        if (!mounted) return;
        final nav = Navigator.of(context);
        final rootContext = nav.context;
        nav.pop();
        NxToast.ok(
          'Product created',
          '${created.sku} · ${created.name}',
          NxToastAction('Receive stock', () => showReceiveSheet(rootContext, productId: created.id)),
        );
      }
    } on AppError catch (e) {
      final m = e.message.toLowerCase();
      setState(() {
        if (m.contains('sku')) {
          _errors['sku'] = e.message;
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
    final categories = ref.watch(categoriesProvider(true)).value ?? const <Category>[];
    final types = ref.watch(attributeTypesProvider(false)).value ?? const <AttributeType>[];
    final uoms = {...kDefaultUoms, ...(ref.watch(productsListProvider).value ?? const <Product>[]).map((p) => p.uom), _uom}.toList()
      ..sort();
    final byId = {for (final c in categories) c.id: c};
    final catOptions = [
      for (final c in categories.where((c) => c.isActive || c.id == _categoryId))
        NxOption(
          c.id,
          c.parentId != null && byId[c.parentId] != null ? '${byId[c.parentId]!.name} › ${c.name}' : c.name,
          sub: c.workstream?.name,
        ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return NxDialogFrame(
      title: _editing ? 'Edit product' : 'New product',
      sub: _editing
          ? '${widget.product!.sku} · stock changes only through receiving, transfers and adjustments'
          : 'Adds a catalogue item. Stock arrives through receiving — never set here.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxFormGrid(
            children: [
              NxField(
                label: 'SKU',
                required: true,
                error: _errors['sku'],
                hint: _editing ? 'Printed QR labels keep working — they use the product’s permanent code' : null,
                child: NxInput(controller: _sku, placeholder: 'P-1013', error: _errors['sku'] != null),
              ),
              NxField(
                label: 'Name',
                required: true,
                error: _errors['name'],
                child: NxInput(controller: _name, placeholder: 'e.g. Cake Flour 2.5kg', error: _errors['name'] != null),
              ),
              NxSpan2(
                child: NxField(
                  label: 'Category',
                  required: true,
                  error: _errors['category'],
                  child: NxSelect<String>(
                    options: catOptions,
                    value: _categoryId,
                    searchable: true,
                    searchPlaceholder: 'Search categories',
                    error: _errors['category'] != null,
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
              ),
              NxField(
                label: 'Unit of measure',
                required: true,
                child: NxSelect<String>(
                  options: [for (final u in uoms) NxOption(u, u)],
                  value: _uom,
                  onChanged: (v) => setState(() => _uom = v ?? _uom),
                ),
              ),
              NxField(
                label: 'Min stock level',
                required: true,
                error: _errors['min'],
                child: NxInput(controller: _min, inputFormatters: NxInput.decimals(), error: _errors['min'] != null),
              ),
              NxField(
                label: 'Selling price',
                required: true,
                error: _errors['price'],
                child: NxInput(controller: _price, inputFormatters: NxInput.decimals(2), error: _errors['price'] != null),
              ),
              NxField(
                label: 'Cost price',
                hint: 'Leave empty to exclude from valuation',
                error: _errors['cost'],
                child: NxInput(controller: _cost, inputFormatters: NxInput.decimals(2), error: _errors['cost'] != null),
              ),
              if (!_editing)
                NxField(
                  label: 'Stock tracking',
                  hint: 'Serial gives every physical unit its own scannable code — the received/counted '
                      'quantity always comes from distinct scans, never typed. Can\'t be changed after creation.',
                  child: NxSelect<TrackingMode>(
                    options: [for (final m in TrackingMode.values) NxOption(m, m.label)],
                    value: _trackingMode,
                    onChanged: (v) => setState(() => _trackingMode = v ?? _trackingMode),
                  ),
                )
              else if (_trackingMode == TrackingMode.serial)
                NxField(
                  label: 'Stock tracking',
                  child: Text('Serial — one scannable code per physical unit', style: TextStyle(fontSize: 13, color: n.n300)),
                ),
              for (final t in types)
                NxField(
                  label: t.unit == null || t.unit!.isEmpty ? t.name : '${t.name} (${t.unit})',
                  hint: 'Attribute · ${t.code}',
                  error: _errors['attr:${t.id}'],
                  child: NxInput(
                    controller: _attrController(t),
                    inputFormatters: t.dataType == AttributeDataType.number ? NxInput.decimals() : null,
                    error: _errors['attr:${t.id}'] != null,
                  ),
                ),
              NxSpan2(
                child: NxField(
                  label: 'Description',
                  child: NxInput(controller: _desc, maxLines: 4, minLines: 3),
                ),
              ),
            ],
          ),
          if (_editing) ...[const SizedBox(height: 14), _ImagesEditor(productId: widget.product!.id)],
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad)),
          ],
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: _saving ? null : () => Navigator.of(context).pop()),
        NxButton.primary(
          label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Create product'),
          onPressed: _saving ? null : () => _submit(types),
        ),
      ],
    );
  }
}

/// The edit dialog's images strip: thumbnails (the primary starred), upload,
/// make primary, remove. Each change saves immediately.
class _ImagesEditor extends ConsumerStatefulWidget {
  const _ImagesEditor({required this.productId});

  final String productId;

  @override
  ConsumerState<_ImagesEditor> createState() => _ImagesEditorState();
}

class _ImagesEditorState extends ConsumerState<_ImagesEditor> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      invalidateProduct(ref, widget.productId);
      NxToast.ok(done);
    } on AppError catch (e) {
      NxToast.error('Image not changed', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final product = ref.watch(productDetailProvider(widget.productId)).value;
    final images = product?.images ?? const [];
    final api = ref.read(productsApiProvider);
    return NxField(
      label: 'Images',
      hint: 'JPEG, PNG or WebP. The starred image is shown in lists.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final img in images)
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: n.n900,
                borderRadius: BorderRadius.circular(NxRadius.md),
                border: Border.all(color: img.isPrimary ? n.accent : n.n800),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImageView(image: img, productId: widget.productId),
                  Positioned(
                    left: 2,
                    top: 2,
                    child: _Tiny(
                      icon: img.isPrimary ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
                      tooltip: img.isPrimary ? 'Primary image' : 'Make primary',
                      color: img.isPrimary ? n.warn : n.n200,
                      onTap: img.isPrimary || _busy ? null : () => _run(() => api.setImagePrimary(widget.productId, img.id), 'Primary image changed'),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: _Tiny(
                      icon: PhosphorIconsRegular.trash,
                      tooltip: 'Remove image',
                      color: n.bad,
                      onTap: _busy ? null : () => _run(() => api.deleteImage(widget.productId, img.id), 'Image removed'),
                    ),
                  ),
                ],
              ),
            ),
          DeviceImagePicker(
            enabled: !_busy,
            label: images.isEmpty ? 'Upload image' : 'Add image',
            onPicked: (Uint8List bytes, String name) => _run(
              () => api.addImageUpload(widget.productId, bytes: bytes, fileName: name, isPrimary: images.isEmpty),
              'Image uploaded',
            ),
          ),
        ],
      ),
    );
  }
}

class _Tiny extends StatelessWidget {
  const _Tiny({required this.icon, required this.tooltip, required this.color, this.onTap});

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: n.bg.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Icon(icon, size: 12, color: color),
          ),
        ),
      ),
    );
  }
}
