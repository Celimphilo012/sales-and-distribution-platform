import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/auth_provider.dart';
import '../core/persistence/shared_preferences_provider.dart';
import '../core/theme/nocturne.dart';
import '../features/orders/data/orders_providers.dart';
import '../features/orders/domain/order.dart';
import '../routing/route_paths.dart';
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

  /// Identity for read/unread tracking — changes when the underlying fact does.
  final String key;
  final IconData icon;
  final Tone tone;
  final String title;
  final String message;
  final String time;

  /// The route tapping it opens.
  final String target;
}

/// The bell's entries, derived from the orders the signed-in user can see:
/// orders waiting for approval / reservation / dispatch (for whoever can act
/// on them), delivered orders still owed money (for whoever records
/// payments), and what happened to your own orders in the last two days.
final consoleNotificationsProvider = FutureProvider.autoDispose<List<ConsoleNotification>>((ref) async {
  final user = ref.watch(authProvider).value?.user;
  if (user == null || !user.canAny(const ['orders.view_team', 'orders.view_own'])) return const [];
  List<Order> orders;
  try {
    orders = await ref.watch(allOrdersProvider.future);
  } catch (_) {
    return const []; // a failing source must never break the bell
  }
  final out = <ConsoleNotification>[];
  String keyOf(String kind, Iterable<Order> list) => '$kind:${list.map((o) => '${o.id}@${o.updatedAt.millisecondsSinceEpoch}').join(',')}';
  DateTime latest(Iterable<Order> list) => list.map((o) => o.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
  String names(Iterable<Order> list) {
    final nums = list.map((o) => o.orderNumber).toList();
    return nums.length <= 3 ? nums.join(', ') : '${nums.take(3).join(', ')} +${nums.length - 3} more';
  }

  void queue(bool allowed, OrderStatus status, IconData icon, Tone tone, String Function(int) title) {
    if (!allowed) return;
    final list = orders.where((o) => o.status == status).toList();
    if (list.isEmpty) return;
    out.add(ConsoleNotification(
      key: keyOf(status.apiValue, list),
      icon: icon,
      tone: tone,
      title: title(list.length),
      message: names(list),
      time: fmtWhen(latest(list)),
      target: '${RoutePaths.orders}?status=${status.apiValue}',
    ));
  }

  String s(int n) => n == 1 ? '' : 's';
  queue(user.can('orders.approve'), OrderStatus.pendingApproval, PhosphorIconsFill.hourglassMedium, Tone.warn, (n) => '$n order${s(n)} waiting for approval');
  queue(user.can('orders.approve'), OrderStatus.approved, PhosphorIconsFill.lockKey, Tone.info, (n) => '$n approved order${s(n)} to reserve stock for');
  queue(user.can('fulfilment.dispatch'), OrderStatus.readyForDispatch, PhosphorIconsFill.truck, Tone.accent, (n) => '$n order${s(n)} ready to dispatch');

  if (user.can('payments.record')) {
    final owed = orders
        .where((o) => (o.status == OrderStatus.delivered || o.status == OrderStatus.completed) && o.paymentStatus != PaymentStatus.paid)
        .toList();
    if (owed.isNotEmpty) {
      out.add(ConsoleNotification(
        key: keyOf('owed', owed),
        icon: PhosphorIconsFill.wallet,
        tone: Tone.bad,
        title: '${owed.length} delivered order${s(owed.length)} not fully paid',
        message: names(owed),
        time: fmtWhen(latest(owed)),
        target: '${RoutePaths.orders}?unpaid=1',
      ));
    }
  }

  // My own orders' recent outcomes (a consultant hears what happened).
  final cutoff = DateTime.now().subtract(const Duration(days: 2));
  const outcomes = {
    OrderStatus.approved: ('approved', Tone.ok, PhosphorIconsFill.checkCircle),
    OrderStatus.rejected: ('rejected', Tone.bad, PhosphorIconsFill.xCircle),
    OrderStatus.dispatched: ('dispatched', Tone.accent, PhosphorIconsFill.truck),
    OrderStatus.delivered: ('delivered', Tone.ok, PhosphorIconsFill.package),
  };
  final mine = orders.where((o) => o.consultantId == user.id && o.updatedAt.isAfter(cutoff) && outcomes.containsKey(o.status)).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  for (final o in mine.take(4)) {
    final (word, tone, icon) = outcomes[o.status]!;
    out.add(ConsoleNotification(
      key: 'mine:${o.id}:${o.status.apiValue}',
      icon: icon,
      tone: tone,
      title: 'Your order ${o.orderNumber} was $word',
      message: '${o.customer.name} · ${fmtMoney(o.total)}',
      time: fmtWhen(o.updatedAt),
      target: RoutePaths.orderDetail(o.id),
    ));
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
