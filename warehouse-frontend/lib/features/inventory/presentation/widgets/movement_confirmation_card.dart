import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../data/inventory_providers.dart';

/// One location's fresh balance after a receive/transfer — the concrete
/// "did this actually land?" proof, fetched via the same `/inventory/
/// balances` endpoint 6d's views use (never trusting the write response
/// alone, since the write endpoints don't return a balance — they return
/// the ledger row).
class MovementLocationResult {
  const MovementLocationResult({required this.label, required this.locationId});

  final String label;
  final String locationId;
}

/// Shown after a successful receive or transfer: the resulting balance at
/// each affected location, plus a link into 6d's "where is this product"
/// view for that exact product — makes the write→read loop visible without
/// rebuilding 6d (per the 6e-1 spec).
class MovementConfirmationCard extends StatelessWidget {
  const MovementConfirmationCard({
    super.key,
    required this.title,
    required this.productId,
    required this.locations,
  });

  final String title;
  final String productId;
  final List<MovementLocationResult> locations;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final location in locations) ...[
            _BalanceRow(productId: productId, result: location),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextButton.icon(
            onPressed: () => context.go('${RoutePaths.inventory}?productId=$productId'),
            icon: const Icon(Icons.travel_explore_outlined),
            label: const Text('Open in "Where is this product?"'),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends ConsumerWidget {
  const _BalanceRow({required this.productId, required this.result});

  final String productId;
  final MovementLocationResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(
      productLocationBalanceProvider((productId: productId, locationId: result.locationId)),
    );

    return balanceAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(result.label, style: theme.textTheme.bodyMedium)),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
      error: (error, stackTrace) => Text(
        '${result.label}: could not load the updated balance.',
        style: TextStyle(color: theme.colorScheme.error),
      ),
      data: (balance) {
        final onHand = balance == null ? 0.0 : balance.onHand;
        final reserved = balance == null ? 0.0 : balance.reserved;
        final available = balance == null ? 0.0 : balance.available;
        return Row(
          children: [
            Expanded(child: Text(result.label, style: theme.textTheme.bodyMedium)),
            _Stat(label: 'On hand', value: onHand),
            const SizedBox(width: AppSpacing.lg),
            _Stat(label: 'Reserved', value: reserved, color: reserved > 0 ? theme.colorScheme.error : null),
            const SizedBox(width: AppSpacing.lg),
            _Stat(label: 'Available', value: available, color: theme.colorScheme.primary, emphasize: true),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color, this.emphasize = false});

  final String label;
  final double value;
  final Color? color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          formatQuantity(value),
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
