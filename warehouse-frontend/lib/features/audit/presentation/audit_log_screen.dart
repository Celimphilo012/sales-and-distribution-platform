import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';

/// STEP 6f — AUDIT LOG. Permission-gated (`audit.view`) as specified, but
/// the screen itself is an honest gap notice rather than a fake viewer: the
/// warehouse backend has a global `AuditInterceptor` that WRITES one
/// `audit_logs` row per successful mutating request, but there is no
/// controller anywhere that READS them back (confirmed — every
/// `@Controller(...)` in `warehouse/src` was inspected; none serves
/// `audit_logs`). Building a list/filter/pagination UI against a
/// nonexistent endpoint would either fake data or show a raw 404 — neither
/// is honest, so this reports the gap instead (see [AuditLog] for the ready
/// domain model once a read endpoint exists).
///
/// BACKEND GAP: add a `GET /audit-logs` (or similar) endpoint, gated
/// `audit.view`, with filters (userId, entity, entityId, action, date range)
/// and pagination, mirroring `audit_logs`' existing `[entity, entityId]` /
/// `[userId]` indexes. Once it exists, this screen becomes a normal list
/// screen — reuse the `AppDataTable` + filter-bar pattern from
/// `UsersScreen`/`RolesScreen`, which this whole feature is a template for.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(authProvider.select((s) => s.value?.user?.can('audit.view') ?? false));
    if (!canView) {
      return const EmptyStateView(
        title: "You don't have permission to view the audit log",
        message: 'Ask an administrator for the audit.view permission.',
        icon: Icons.lock_outline,
      );
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Audit Log', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AppCard(
              title: 'Not available yet',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'The warehouse backend writes an audit_logs row for every mutating '
                          'request, but does not yet expose an endpoint to read them back. '
                          'There is nothing this screen can honestly show until that endpoint '
                          'exists — see CLAUDE.md for this as a reported backend gap.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'What this screen will do once the read endpoint exists: a paginated, '
                    'newest-first list with filters for user, entity, entity id, action, and '
                    'date range, showing old/new values where present — the domain model '
                    '(AuditLog) already mirrors the real audit_logs row shape.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
