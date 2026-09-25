import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/date_format.dart';
import '../../../../shared/quantity_format.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../data/stock_adjustments_providers.dart';
import '../../domain/stock_adjustment.dart';

/// One adjustment's summary card: product/location/bucket, signed delta,
/// status pill, requester + reason, an attached evidence photo if present,
/// and (once reviewed) reviewer + note. Reused by the pending queue (so a
/// manager sees and can open the photo right where Approve/Reject live, not
/// behind an extra click), the approved/rejected history, and the
/// stock-count detail screen's "adjustments created from this count" list —
/// one rendering of a [StockAdjustment] everywhere it shows up.
class AdjustmentSummaryTile extends ConsumerWidget {
  const AdjustmentSummaryTile({super.key, required this.adjustment, this.trailing});

  final StockAdjustment adjustment;

  /// Approve/reject controls, or a "you requested this" note — supplied by
  /// the caller so this widget stays a pure renderer with no permission
  /// logic of its own.
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (adjustment.hasPhoto) ...[
            const SizedBox(height: AppSpacing.sm),
            _PhotoThumbnail(adjustment: adjustment),
          ],
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

/// A small tappable evidence-photo preview. Fetches bytes lazily (only when
/// this tile is actually built, i.e. only for adjustments that have one —
/// see [adjustmentPhotoProvider]) and opens full-size on tap so a reviewer
/// can inspect it before approving/rejecting, right on the card the
/// approve/reject buttons live on.
class _PhotoThumbnail extends ConsumerWidget {
  const _PhotoThumbnail({required this.adjustment});

  final StockAdjustment adjustment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photoAsync = ref.watch(adjustmentPhotoProvider(adjustment.id));

    return photoAsync.when(
      loading: () => const SizedBox(
        width: 64,
        height: 64,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (error, stackTrace) => Row(
        children: [
          Icon(Icons.broken_image_outlined, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Photo attached, but could not be loaded',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ),
      data: (bytes) => InkWell(
        onTap: () => _openFullSize(context, bytes),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
        ),
      ),
    );
  }

  void _openFullSize(BuildContext context, Uint8List bytes) {
    AppDialog.show<void>(
      context,
      title: '${adjustment.product.name} — evidence photo',
      content: Image.memory(bytes, fit: BoxFit.contain),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
