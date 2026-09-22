import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_loading_error_states.dart';
import '../../data/catalogue_providers.dart';
import '../../domain/warehouse_product.dart';

/// Debounced product search against `/backend`'s catalogue relay (STEP
/// R3a). A blank query still lists the (active-only) catalogue — this app's
/// product set is small enough that browsing without typing first is more
/// useful than an empty state. Tapping a result calls [onSelected]; this
/// widget owns only the search box + result list.
class ProductSearchField extends ConsumerStatefulWidget {
  const ProductSearchField({super.key, required this.onSelected});

  final ValueChanged<WarehouseProduct> onSelected;

  @override
  ConsumerState<ProductSearchField> createState() => _ProductSearchFieldState();
}

class _ProductSearchFieldState extends ConsumerState<ProductSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(catalogueSearchResultsProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Search for a product',
          controller: _controller,
          hintText: 'SKU or name',
          prefixIcon: Icons.search,
          onChanged: _onChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        resultsAsync.when(
          loading: () => const LoadingStateView(),
          error: (error, stackTrace) => ErrorStateView(
            message: error is AppError ? error.message : 'Could not search the catalogue.',
            onRetry: () => ref.invalidate(catalogueSearchResultsProvider(_query)),
          ),
          data: (results) {
            if (results.isEmpty) {
              return const EmptyStateView(title: 'No matching products', icon: Icons.search_off);
            }
            return Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: results.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = results[index];
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text(
                      '${product.sku} · ${product.category?.name ?? 'Uncategorized'} · '
                      '${formatQuantity(product.sellingPrice)}/${product.uom}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onSelected(product),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
