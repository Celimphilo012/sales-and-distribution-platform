import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/device_image_picker.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../attribute_types/data/attribute_types_providers.dart';
import '../../attribute_types/domain/attribute_type.dart';
import '../../categories/data/categories_providers.dart';
import '../../categories/domain/category_tree.dart';
import '../../workstreams/data/workstreams_providers.dart';
import '../data/products_providers.dart';
import '../domain/product.dart';
import '../domain/product_attribute.dart';
import '../domain/product_image.dart';
import 'products_list_providers.dart';
import 'widgets/product_image_view.dart';

/// Create/edit form — one dedicated routed screen for both, since products
/// have too many fields for a dialog. `productId == null` means create.
class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    if (!canManage) {
      return const EmptyStateView(
        title: "You don't have permission to manage products",
        message: 'Ask an administrator for the products.manage permission.',
        icon: Icons.lock_outline,
      );
    }

    if (productId == null) {
      return const _ProductFormBody(initialProduct: null);
    }

    final productAsync = ref.watch(productDetailProvider(productId!));
    return productAsync.when(
      loading: () => const LoadingStateView(message: 'Loading product…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load this product.',
        onRetry: () => ref.invalidate(productDetailProvider(productId!)),
      ),
      data: (product) => _ProductFormBody(initialProduct: product),
    );
  }
}

/// Built exactly once data is ready (see [ProductFormScreen] gating on
/// [productDetailProvider] before constructing this) so every field —
/// including the category dropdown — gets the right value on its very
/// first build, instead of racing an async load.
class _ProductFormBody extends ConsumerStatefulWidget {
  const _ProductFormBody({required this.initialProduct});

  final Product? initialProduct;

  @override
  ConsumerState<_ProductFormBody> createState() => _ProductFormBodyState();
}

class _ProductFormBodyState extends ConsumerState<_ProductFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _skuController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _uomController;
  late final TextEditingController _minStockController;
  String? _workstreamId;
  String? _categoryId;
  bool _saving = false;
  String? _errorMessage;

  // Lazily created per attribute type once its row first renders (the type
  // catalog loads async) — NOT recreated on every rebuild, so typed text
  // and cursor position survive. Descriptive metadata only (colour, size,
  // weight, ...); this never touches inventory/stock.
  final Map<String, TextEditingController> _attributeControllers = {};

  bool get _isEditing => widget.initialProduct != null;

  TextEditingController _attributeControllerFor(AttributeType type) {
    return _attributeControllers.putIfAbsent(type.id, () {
      final productAttributes = widget.initialProduct?.attributes ?? const <ProductAttribute>[];
      final existing = _firstOrNull(productAttributes.where((a) => a.attributeTypeId == type.id));
      return TextEditingController(text: existing?.value ?? '');
    });
  }

  @override
  void initState() {
    super.initState();
    final p = widget.initialProduct;
    _skuController = TextEditingController(text: p?.sku ?? '');
    _nameController = TextEditingController(text: p?.name ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _sellingPriceController = TextEditingController(text: p != null ? _formatNumber(p.sellingPrice) : '');
    _costPriceController = TextEditingController(
      text: p?.costPrice != null ? _formatNumber(p!.costPrice!) : '',
    );
    _uomController = TextEditingController(text: p?.uom ?? '');
    _minStockController = TextEditingController(text: p != null ? _formatNumber(p.minStockLevel) : '0');
    _workstreamId = p?.category?.workstreamId;
    _categoryId = p?.categoryId;
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _uomController.dispose();
    _minStockController.dispose();
    for (final controller in _attributeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Reads every active attribute type's controller and builds the payload
  /// — a blank field means "no value for this attribute" (omitted, not an
  /// empty string). A NUMBER-dataType field must parse as a number; on
  /// failure this sets [_errorMessage] and returns `null`.
  List<ProductAttributeInput>? _resolveAttributes() {
    final types = ref.read(attributeTypesProvider(false)).value ?? const [];
    final attributes = <ProductAttributeInput>[];

    for (final type in types) {
      final text = _attributeControllerFor(type).text.trim();
      if (text.isEmpty) continue;

      if (type.dataType == AttributeDataType.number) {
        final n = double.tryParse(text);
        if (n == null) {
          setState(() => _errorMessage = '"${type.name}" must be a number.');
          return null;
        }
        attributes.add(ProductAttributeInput(attributeTypeId: type.id, value: n));
      } else {
        attributes.add(ProductAttributeInput(attributeTypeId: type.id, value: text));
      }
    }

    return attributes;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      setState(() => _errorMessage = 'Please choose a category.');
      return;
    }
    final attributes = _resolveAttributes();
    if (attributes == null) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final api = ref.read(productsApiProvider);
    try {
      final sellingPrice = double.parse(_sellingPriceController.text.trim());
      final costPriceText = _costPriceController.text.trim();
      final costPrice = costPriceText.isEmpty ? null : double.parse(costPriceText);
      final minStockText = _minStockController.text.trim();
      final minStock = minStockText.isEmpty ? 0.0 : double.parse(minStockText);
      final description = _descriptionController.text.trim();

      if (_isEditing) {
        final id = widget.initialProduct!.id;
        await api.update(
          id,
          name: _nameController.text.trim(),
          description: description,
          categoryId: _categoryId!,
          sellingPrice: sellingPrice,
          costPrice: costPrice,
          uom: _uomController.text.trim(),
          minStockLevel: minStock,
          attributes: attributes,
        );
        invalidateProduct(ref, id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product saved')));
          context.go(RoutePaths.productDetail(id));
        }
      } else {
        final created = await api.create(
          sku: _skuController.text.trim(),
          name: _nameController.text.trim(),
          description: description,
          categoryId: _categoryId!,
          sellingPrice: sellingPrice,
          costPrice: costPrice,
          uom: _uomController.text.trim(),
          minStockLevel: minStock,
          attributes: attributes,
        );
        ref.invalidate(productsListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product created')));
          // Land on edit (not detail) so the image-URL section — only
          // available once the product exists — is immediately usable.
          context.go(RoutePaths.productEdit(created.id));
        }
      }
    } on AppError catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workstreamsAsync = ref.watch(workstreamsProvider(false));
    final categoriesAsync = ref.watch(categoriesProvider(false));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => context.go(
                _isEditing ? RoutePaths.productDetail(widget.initialProduct!.id) : RoutePaths.products,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(_isEditing ? 'Edit product' : 'New product', style: theme.textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'SKU',
                    controller: _skuController,
                    enabled: !_isEditing,
                    helperText: _isEditing ? 'SKU cannot be changed after creation' : null,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'SKU is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Name',
                    controller: _nameController,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(label: 'Description', controller: _descriptionController, maxLines: 3),
                  const SizedBox(height: AppSpacing.md),
                  // Category picker reflects the Workstream -> Category ->
                  // sub-category hierarchy: pick a workstream, then a
                  // category scoped to it (same "narrow the choices" idiom
                  // as the category-management dialog and the
                  // leaf-location picker) — a product has no workstream of
                  // its own, it's implied by whichever category is chosen.
                  workstreamsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stackTrace) => Text(
                      'Could not load workstreams',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    data: (workstreams) => AppDropdownField<String>(
                      label: 'Workstream',
                      value: _workstreamId,
                      items: [for (final w in workstreams) w.id],
                      itemLabel: (id) => workstreams.firstWhere((w) => w.id == id).name,
                      onChanged: (value) => setState(() {
                        _workstreamId = value;
                        // A category from the old workstream isn't valid
                        // for the new one.
                        _categoryId = null;
                      }),
                      validator: (v) => v == null ? 'Choose a workstream' : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  categoriesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stackTrace) => Text(
                      'Could not load categories',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    data: (categories) {
                      if (_workstreamId == null) {
                        return Text(
                          'Choose a workstream first',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        );
                      }
                      final tree = buildCategoryTreeForWorkstream(categories, _workstreamId!);
                      final flat = flattenCategoryTree(tree);
                      return AppDropdownField<String>(
                        label: 'Category',
                        value: flat.any((n) => n.category.id == _categoryId) ? _categoryId : null,
                        items: [for (final node in flat) node.category.id],
                        itemLabel: (id) {
                          final node = flat.firstWhere((n) => n.category.id == id);
                          return '${'    ' * node.depth}${node.category.name}';
                        },
                        onChanged: (value) => setState(() => _categoryId = value),
                        validator: (v) => v == null ? 'Choose a category' : null,
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppNumberField(
                          label: 'Selling price',
                          controller: _sellingPriceController,
                          allowDecimal: true,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n <= 0) return 'Enter a price greater than 0';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppNumberField(
                          label: 'Cost price (optional)',
                          controller: _costPriceController,
                          allowDecimal: true,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = double.tryParse(v);
                            if (n == null || n < 0) return 'Enter a valid cost price';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Unit of measure',
                          controller: _uomController,
                          hintText: 'EACH, KG, BOX…',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'UOM is required' : null,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppNumberField(
                          label: 'Min stock level',
                          controller: _minStockController,
                          allowDecimal: true,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = double.tryParse(v);
                            if (n == null || n < 0) return 'Must be 0 or more';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _AttributesSection(attributeControllerFor: _attributeControllerFor),
        ),
        if (_isEditing) ...[
          const SizedBox(height: AppSpacing.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _ProductImagesEditor(productId: widget.initialProduct!.id, images: widget.initialProduct!.images),
          ),
        ],
      ],
    );
  }
}

T? _firstOrNull<T>(Iterable<T> iterable) {
  for (final item in iterable) {
    return item;
  }
  return null;
}

/// Driven entirely by the attribute-TYPE catalog — a new active type shows
/// up here automatically, no frontend change needed (the extensibility the
/// backend model was built for). One field per active type: a number field
/// (with its unit, if any, shown as a suffix) for NUMBER types, a text
/// field otherwise. Descriptive metadata only — NOT variants, never touches
/// stock/inventory.
class _AttributesSection extends ConsumerWidget {
  const _AttributesSection({required this.attributeControllerFor});

  final TextEditingController Function(AttributeType type) attributeControllerFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attributeTypesAsync = ref.watch(attributeTypesProvider(false));

    return AppCard(
      title: 'Attributes',
      subtitle: 'Descriptive metadata (colour, size, weight, ...) — optional, not variants',
      child: attributeTypesAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, stackTrace) => Text(
          'Could not load attribute types',
          style: TextStyle(color: theme.colorScheme.error),
        ),
        data: (attributeTypes) {
          if (attributeTypes.isEmpty) {
            return Text(
              'No attribute types yet.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final type in attributeTypes) ...[
                if (type.dataType == AttributeDataType.number)
                  AppNumberField(
                    label: (type.unit?.isNotEmpty ?? false) ? '${type.name} (${type.unit})' : type.name,
                    controller: attributeControllerFor(type),
                    allowDecimal: true,
                  )
                else
                  AppTextField(
                    label: (type.unit?.isNotEmpty ?? false) ? '${type.name} (${type.unit})' : type.name,
                    controller: attributeControllerFor(type),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}

class _ProductImagesEditor extends ConsumerStatefulWidget {
  const _ProductImagesEditor({required this.productId, required this.images});

  final String productId;
  final List<ProductImage> images;

  @override
  ConsumerState<_ProductImagesEditor> createState() => _ProductImagesEditorState();
}

class _ProductImagesEditorState extends ConsumerState<_ProductImagesEditor> {
  final _urlController = TextEditingController();
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addImage(List<ProductImage> currentImages) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ref
          .read(productsApiProvider)
          .addImage(widget.productId, url: url, isPrimary: currentImages.isEmpty);
      _urlController.clear();
      ref.invalidate(productDetailProvider(widget.productId));
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _uploadImage(List<ProductImage> currentImages, Uint8List bytes, String fileName) async {
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ref
          .read(productsApiProvider)
          .addImageUpload(widget.productId, bytes: bytes, fileName: fileName, isPrimary: currentImages.isEmpty);
      ref.invalidate(productDetailProvider(widget.productId));
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _setPrimary(String imageId) async {
    try {
      await ref.read(productsApiProvider).setImagePrimary(widget.productId, imageId);
      ref.invalidate(productDetailProvider(widget.productId));
    } on AppError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeImage(String imageId) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Remove image?',
      message: 'This removes the image from the product.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(productsApiProvider).deleteImage(widget.productId, imageId);
      ref.invalidate(productDetailProvider(widget.productId));
    } on AppError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-watch so this list reflects mutations immediately — `widget.images`
    // is just this widget's construction-time snapshot.
    final productAsync = ref.watch(productDetailProvider(widget.productId));
    final images = productAsync.value?.images ?? widget.images;
    final theme = Theme.of(context);

    return AppCard(
      title: 'Images',
      subtitle: 'Paste an image URL, or upload one from this device',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final image in images)
                  _ImageTile(
                    image: image,
                    productId: widget.productId,
                    onSetPrimary: image.isPrimary ? null : () => _setPrimary(image.id),
                    onRemove: () => _removeImage(image.id),
                  ),
              ],
            )
          else
            Text(
              'No images yet.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Image URL',
                  controller: _urlController,
                  hintText: 'https://…',
                  enabled: !_adding,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _adding ? null : () => _addImage(images),
                icon: const Icon(Icons.add_link),
                label: const Text('Add'),
              ),
              const SizedBox(width: AppSpacing.sm),
              DeviceImagePicker(
                enabled: !_adding,
                onPicked: (bytes, fileName) => _uploadImage(images, bytes, fileName),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image, required this.productId, required this.onSetPrimary, required this.onRemove});

  final ProductImage image;
  final String productId;
  final VoidCallback? onSetPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 140,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border.all(
          color: image.isPrimary ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: SizedBox(
              width: double.infinity,
              height: 90,
              child: ProductImageView(image: image, productId: productId),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (image.isPrimary)
            const StatusBadge(label: 'Primary', tone: StatusTone.info)
          else
            TextButton(onPressed: onSetPrimary, child: const Text('Set primary')),
          IconButton(iconSize: 18, tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: onRemove),
        ],
      ),
    );
  }
}
