import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/app_error.dart';
import '../../routing/route_paths.dart';
import '../../shared/nx/nx_list_page.dart';
import '../../shared/nx/nx_overlays.dart';
import '../../shared/scan/scan_code.dart';
import '../../shared/scan/scan_dialog.dart';
import '../locations/data/leaf_locations_provider.dart';
import '../products/data/products_providers.dart';
import '../products/domain/product.dart';
import '../products/domain/products_filter.dart';
import '../products/presentation/product_sheet.dart';

/// The product a scan points at among [products] (by permanent id, or by SKU
/// for a code that is not one of our labels).
Product? matchScannedProduct(ScanCode code, Iterable<Product> products) =>
    code.match(ScanKind.product, products, id: (p) => p.id, code: (p) => p.sku);

/// The storage slot a scan points at among [leaves] (by id, or by location code).
LeafLocation? matchScannedLeaf(ScanCode code, Iterable<LeafLocation> leaves) =>
    code.match(ScanKind.location, leaves, id: (l) => l.id, code: (l) => l.code);

/// Scans a product for a picker; returns its id, or null (with a toast when
/// the code matched nothing).
Future<String?> scanProductId(BuildContext context, Iterable<Product> products) async {
  final code = await showScanDialog(context, title: 'Scan a product', sub: 'Scan the product’s QR label (or its SKU barcode).');
  if (code == null || code.isEmpty) return null;
  final p = matchScannedProduct(code, products);
  if (p == null) NxToast.error('No matching product', code.kind == ScanKind.location ? 'That is a location label.' : 'Nothing here has the code “${code.value}”.');
  return p?.id;
}

/// Scans a storage slot for a picker; returns its id, or null (with a toast
/// when the code matched nothing selectable).
Future<String?> scanLeafId(BuildContext context, Iterable<LeafLocation> leaves) async {
  final code = await showScanDialog(context, title: 'Scan a location', sub: 'Scan the QR label on the shelf or bin.');
  if (code == null || code.isEmpty) return null;
  final l = matchScannedLeaf(code, leaves);
  if (l == null) {
    NxToast.error(
      'No matching slot',
      code.kind == ScanKind.product ? 'That is a product label.' : 'No active storage slot you can use has that code.',
    );
  }
  return l?.id;
}

/// The top-bar scan: a product opens its sheet; a location opens Inventory
/// filtered to "what's here".
Future<void> scanAndOpen(BuildContext context, WidgetRef ref) async {
  final code = await showScanDialog(context, title: 'Scan', sub: 'A product label opens the product; a location label shows what is stored there.');
  if (code == null || code.isEmpty || !context.mounted) return;

  Future<void> openLocation(String id) async {
    ref.read(nxListStatesProvider.notifier).preset('inventory', filters: {'loc': id});
    context.go(RoutePaths.inventory);
  }

  try {
    if (code.kind == ScanKind.location) return openLocation(code.value);
    final api = ref.read(productsApiProvider);
    if (code.kind == ScanKind.product) {
      await api.getById(code.value);
      if (context.mounted) await showProductSheet(context, code.value);
      return;
    }
    // Not one of our labels: try it as a SKU, then as a location code.
    final hits = await api.list(ProductsFilter(search: code.value, includeInactive: true));
    final p = matchScannedProduct(code, hits);
    if (p != null) {
      if (context.mounted) await showProductSheet(context, p.id);
      return;
    }
    final leaves = await ref.read(leafLocationsProvider.future);
    final l = matchScannedLeaf(code, leaves);
    if (l != null) return openLocation(l.id);
    NxToast.error('Nothing found', 'No product or location has the code “${code.value}”.');
  } on AppError catch (e) {
    NxToast.error('Nothing found', e is NotFoundError ? 'That label’s product no longer exists.' : e.message);
  }
}
