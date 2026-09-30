import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/auth_provider.dart';
import '../core/persistence/shared_preferences_provider.dart';
import '../core/theme/nocturne.dart';
import '../features/dashboard/data/dashboard_providers.dart';
import '../features/dashboard/domain/dashboard_summary.dart';
import '../features/stock_adjustments/data/stock_adjustments_providers.dart';
import '../features/stock_adjustments/domain/stock_adjustment.dart';
import '../features/stock_counts/data/stock_counts_providers.dart';
import '../features/stock_counts/domain/stock_count.dart';
import '../shared/nx/nx_format.dart';

/// One entry in the top bar's notifications panel.
class ConsoleNotification {
  const ConsoleNotification({
    required this.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    required this.time,
    required this.target,
  });

  /// Identity for read/unread tracking — changes when the underlying fact
  /// changes (a new pending request, a different on-hand figure).
  final String key;
  final IconData icon;
  final Tone tone;
  final String title;
  final String message;
  final String time;

  /// Where tapping it goes: a route path, or `product:<id>` for a product sheet.
  final String target;
}

/// The notifications panel's entries, derived from live data the signed-in
/// user is allowed to see — the same three kinds as the Warehouse Console
/// prototype: adjustments waiting for review, products below minimum, and
/// recently submitted stock counts. Sources the user lacks permission for are
/// simply skipped (a 403 must never break the bell).
final consoleNotificationsProvider = FutureProvider.autoDispose<List<ConsoleNotification>>((ref) async {
  final user = ref.watch(authProvider).value?.user;
  if (user == null) return const [];
  final out = <ConsoleNotification>[];

  Future<T?> safe<T>(Future<T> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  if (user.can('inventory.adjust.approve')) {
    final pending = await safe(ref.watch(stockAdjustmentsListProvider(AdjustmentStatus.pending).future));
    if (pending != null && pending.isNotEmpty) {
      final oldest = pending.reduce((a, b) => a.requestedAt.isBefore(b.requestedAt) ? a : b);
      final newest = pending.reduce((a, b) => a.requestedAt.isAfter(b.requestedAt) ? a : b);
      out.add(
        ConsoleNotification(
          key: 'adj:${pending.length}:${newest.id}',
          icon: PhosphorIconsFill.hourglassMedium,
          tone: Tone.warn,
          title: '${pending.length} adjustment${pending.length == 1 ? '' : 's'} waiting for review',
          message: 'Oldest: ${oldest.product.name}, ${daysSince(oldest.requestedAt)} day${daysSince(oldest.requestedAt) == 1 ? '' : 's'}',
          time: fmtWhen(newest.requestedAt),
          target: '/stock-adjustments',
        ),
      );
    }
  }

  if (user.can('reports.view')) {
    final dash = await safe(ref.watch(dashboardSummaryProvider.future));
    for (final p in dash?.lowStock.items.take(3) ?? const <LowStockItem>[]) {
      out.add(
        ConsoleNotification(
          key: 'low:${p.productId}:${p.onHand}',
          icon: PhosphorIconsFill.warning,
          tone: Tone.warn,
          title: '${p.name} below minimum',
          message: '${fmtNum(p.onHand)} on hand · minimum ${fmtNum(p.minStockLevel)}',
          time: 'Now',
          target: 'product:${p.productId}',
        ),
      );
    }
  }

  if (user.can('inventory.count')) {
    final submitted = await safe(ref.watch(stockCountsListProvider(StockCountStatus.submitted).future));
    final recent = (submitted ?? const <StockCount>[])
        .where((c) => c.submittedAt != null && daysSince(c.submittedAt!) <= 2)
        .toList()
      ..sort((a, b) => b.submittedAt!.compareTo(a.submittedAt!));
    for (final c in recent.take(2)) {
      out.add(
        ConsoleNotification(
          key: 'count:${c.id}',
          icon: PhosphorIconsFill.checkCircle,
          tone: Tone.ok,
          title: 'Stock count submitted',
          message: 'At ${c.location.code} by ${c.startedByUser.fullName}',
          time: fmtWhen(c.submittedAt),
          target: '/stock-counts',
        ),
      );
    }
  }
  return out;
});

const _seenKey = 'console.notifications.seen';

/// Which notification keys have been "read" on this device.
class SeenNotifications extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.read(sharedPreferencesProvider).getStringList(_seenKey) ?? const []).toSet();

  Future<void> markAll(Iterable<String> keys) async {
    state = {...state, ...keys};
    // Keep the stored set small: only what is still showing matters.
    await ref.read(sharedPreferencesProvider).setStringList(_seenKey, keys.toList());
  }
}

final seenNotificationsProvider = NotifierProvider<SeenNotifications, Set<String>>(SeenNotifications.new);
