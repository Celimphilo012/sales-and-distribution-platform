import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import 'where_is_this_product_view.dart';
import 'whats_in_this_location_view.dart';

enum _InventoryView { whereIsThisProduct, whatsInThisLocation }

/// STEP 6d — read-only inventory display (never moves stock; that's 6e).
/// Two complementary views behind a segmented toggle:
///  - "Where is this product?" (product-centric, the flagship view)
///  - "What's in this location?" (location-centric — also wired into 6c's
///    Warehouse Structure detail panel, see `location_stock_panel.dart`)
/// The whole screen is reached only with `inventory.view` (gated by the
/// router, same as every other nav destination — see `nav_items.dart`).
///
/// [initialProductId] (from `?productId=`, set by 6e-1's post-receive/
/// -transfer confirmation link) forces the "where is this product" tab open
/// on that product — making the write→read loop visible without duplicating
/// this screen.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, this.initialProductId});

  final String? initialProductId;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  _InventoryView _view = _InventoryView.whereIsThisProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inventory', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<_InventoryView>(
            segments: const [
              ButtonSegment(
                value: _InventoryView.whereIsThisProduct,
                label: Text('Where is this product?'),
                icon: Icon(Icons.travel_explore_outlined),
              ),
              ButtonSegment(
                value: _InventoryView.whatsInThisLocation,
                label: Text("What's in this location?"),
                icon: Icon(Icons.inventory_2_outlined),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (selection) => setState(() => _view = selection.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: switch (_view) {
              _InventoryView.whereIsThisProduct =>
                WhereIsThisProductView(key: ValueKey(widget.initialProductId), initialProductId: widget.initialProductId),
              _InventoryView.whatsInThisLocation => const WhatsInThisLocationView(),
            },
          ),
        ],
      ),
    );
  }
}
