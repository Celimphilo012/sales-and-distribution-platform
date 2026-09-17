import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/date_format.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../domain/stock_adjustment.dart';

/// One adjustment's summary card: product/location/bucket, signed delta,
/// status pill, requester + reason, and (once reviewed) reviewer + note.
/// Reused by the pending queue, the approved/rejected history, and the
/// stock-count detail screen's "adjustments created from this count" list —
/// one rendering of a [StockAdjustment] everywhere it shows up.
class AdjustmentSummaryTile extends StatelessWidget {
  const AdjustmentSummaryTile({super.key, required this.adjustment, this.trailing});

  final StockAdjustment adjustment;

  /// Approve/reject controls, or a "you requested this" note — supplied by
  /// the caller so this widget stays a pure renderer with no permission
  /// logic of its own.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tone, label) = switch (adjustment.status) {
      AdjustmentStatus.pending => (StatusTone.warning, 'Pending'),
      AdjustmentStatus.approved => (StatusTone.success, 'Approved'),
      AdjustmentStatus.rejected => (StatusTone.danger, 'Rejected'),
    };
    final isIncrease = adjustment.direction == AdjustmentDirection.increase;
    final sign = isIncrease ? '+' : '−';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${adjustment.product.name} (${adjustment.product.sku})', style: theme.textTheme.bodyMedium),
                    Text(
                      '${adjustment.location.name} (${adjustment.location.code}) · ${adjustment.bucket.label}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '$sign${formatQuantity(adjustment.delta)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isIncrease ? theme.colorScheme.primary : theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Reason: ${adjustment.reason}', style: theme.textTheme.bodySmall),
          Text(
            'Requested by ${adjustment.requestedByUser.fullName} · ${formatDateTime(adjustment.requestedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (adjustment.reviewedByUser != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${adjustment.status.label} by ${adjustment.reviewedByUser!.fullName}'
                '${adjustment.reviewedAt != null ? ' · ${formatDateTime(adjustment.reviewedAt!)}' : ''}'
                '${(adjustment.reviewNote?.isNotEmpty ?? false) ? ' — "${adjustment.reviewNote}"' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (trailing != null) ...[const SizedBox(height: AppSpacing.sm), trailing!],
        ],
      ),
    );
  }
}
