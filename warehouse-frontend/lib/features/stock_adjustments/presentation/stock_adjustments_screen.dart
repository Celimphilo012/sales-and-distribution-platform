import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../data/stock_adjustments_providers.dart';
import '../domain/stock_adjustment.dart';
import 'widgets/adjustment_request_form.dart';
import 'widgets/adjustment_summary_tile.dart';
import 'widgets/review_note_dialog.dart';

enum _AdjustmentsView { request, queue }

/// STEP 6e-2 — STOCK ADJUSTMENTS, the two-step approval workflow (§F):
/// `inventory.adjust.request` (WAREHOUSE) proposes, `inventory.adjust.
/// approve` (MANAGER) reviews. A request never moves stock; only an approval
/// does (`StockAdjustmentsService.approve` is the sole caller of
/// `InventoryService.applyTransaction()` in this feature). Separation of
/// duties — a requester cannot approve their own request — is enforced on
/// the backend regardless; this screen mirrors it by hiding approve/reject on
/// a user's own pending requests, and still handles a 403 gracefully if one
/// ever slips through (e.g. a stale list racing a permission change).
class StockAdjustmentsScreen extends ConsumerStatefulWidget {
  const StockAdjustmentsScreen({super.key});

  @override
  ConsumerState<StockAdjustmentsScreen> createState() => _StockAdjustmentsScreenState();
}

class _StockAdjustmentsScreenState extends ConsumerState<StockAdjustmentsScreen> {
  _AdjustmentsView _view = _AdjustmentsView.queue;

  void _refresh() {
    ref.invalidate(stockAdjustmentsListProvider(null));
  }

  Future<void> _approve(StockAdjustment adjustment) async {
    final note = await showReviewNoteDialog(
      context,
      title: 'Approve adjustment',
      actionLabel: 'Approve',
      required: false,
    );
    if (note == null || !mounted) return;
    try {
      await ref
          .read(stockAdjustmentsApiProvider)
          .approve(adjustment.id, reviewNote: note.isEmpty ? null : note);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved — stock moved for ${adjustment.product.name}.')),
      );
    } on AppError catch (e) {
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reject(StockAdjustment adjustment) async {
    final note = await showReviewNoteDialog(
      context,
      title: 'Reject adjustment',
      actionLabel: 'Reject',
      required: true,
    );
    if (note == null || !mounted) return;
    try {
      await ref.read(stockAdjustmentsApiProvider).reject(adjustment.id, reviewNote: note);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adjustment rejected — no stock moved.')));
    } on AppError catch (e) {
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final canRequest = user?.can('inventory.adjust.request') ?? false;
    final canApprove = user?.can('inventory.adjust.approve') ?? false;

    if (!canRequest && !canApprove) {
      return const EmptyStateView(
        title: "You don't have permission to view stock adjustments",
        message: 'Ask an administrator for the inventory.adjust.request or inventory.adjust.approve permission.',
        icon: Icons.lock_outline,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stock Adjustments', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<_AdjustmentsView>(
            segments: [
              const ButtonSegment(
                value: _AdjustmentsView.queue,
                label: Text('Queue & history'),
                icon: Icon(Icons.checklist_rtl_outlined),
              ),
              if (canRequest)
                const ButtonSegment(
                  value: _AdjustmentsView.request,
                  label: Text('Request adjustment'),
                  icon: Icon(Icons.request_page_outlined),
                ),
            ],
            selected: {_view},
            onSelectionChanged: (selection) => setState(() => _view = selection.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: switch (_view) {
              _AdjustmentsView.request => canRequest
                  ? SingleChildScrollView(
                      child: AdjustmentRequestForm(onSubmitted: () {
                        _refresh();
                        setState(() => _view = _AdjustmentsView.queue);
                      }),
                    )
                  : const SizedBox.shrink(),
              _AdjustmentsView.queue => _QueueAndHistory(
                  user: user,
                  canApprove: canApprove,
                  onApprove: _approve,
                  onReject: _reject,
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _QueueAndHistory extends ConsumerWidget {
  const _QueueAndHistory({
    required this.user,
    required this.canApprove,
    required this.onApprove,
    required this.onReject,
  });

  final AppUser? user;
  final bool canApprove;
  final void Function(StockAdjustment) onApprove;
  final void Function(StockAdjustment) onReject;

  /// An approver sees every adjustment; a request-only user sees only their
  /// own — `findAll` itself has no "mine" filter (it only gates on
  /// `inventory.view`), so this is a client-side visibility choice, not a
  /// backend restriction.
  List<StockAdjustment> _visible(List<StockAdjustment> all) {
    if (canApprove) return all;
    final uid = user?.id;
    return all.where((a) => a.requestedBy == uid).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adjustmentsAsync = ref.watch(stockAdjustmentsListProvider(null));

    return adjustmentsAsync.when(
      loading: () => const LoadingStateView(message: 'Loading adjustments…'),
      error: (error, stackTrace) => ErrorStateView(
        message: error is AppError ? error.message : 'Could not load adjustments.',
        onRetry: () => ref.invalidate(stockAdjustmentsListProvider(null)),
      ),
      data: (all) {
        final visible = _visible(all);
        final pending = visible.where((a) => a.status == AdjustmentStatus.pending).toList();
        final reviewed = visible.where((a) => a.status != AdjustmentStatus.pending).toList()
          ..sort((a, b) => (b.reviewedAt ?? b.requestedAt).compareTo(a.reviewedAt ?? a.requestedAt));

        if (visible.isEmpty) {
          return const EmptyStateView(
            title: 'No adjustments yet',
            message: 'Requested adjustments — yours or, if you approve, everyone\'s — will show up here.',
            icon: Icons.tune_outlined,
          );
        }

        return ListView(
          children: [
            Text('Pending (${pending.length})', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (pending.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'No pending adjustments.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              for (final adjustment in pending) ...[
                AdjustmentSummaryTile(adjustment: adjustment, trailing: _pendingTrailing(context, theme, adjustment)),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.lg),
            Text('History (${reviewed.length})', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (reviewed.isEmpty)
              Text(
                'No approved or rejected adjustments yet.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (final adjustment in reviewed) ...[
                AdjustmentSummaryTile(adjustment: adjustment),
                const SizedBox(height: AppSpacing.sm),
              ],
          ],
        );
      },
    );
  }

  Widget? _pendingTrailing(BuildContext context, ThemeData theme, StockAdjustment adjustment) {
    final isOwnRequest = user != null && adjustment.requestedBy == user!.id;

    if (!canApprove) {
      return isOwnRequest
          ? Text(
              'Awaiting approval from a manager.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          : null;
    }

    if (isOwnRequest) {
      return Text(
        'You requested this — a different reviewer must approve it.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () => onReject(adjustment),
          icon: const Icon(Icons.close),
          label: const Text('Reject'),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.icon(
          onPressed: () => onApprove(adjustment),
          icon: const Icon(Icons.check),
          label: const Text('Approve'),
        ),
      ],
    );
  }
}
