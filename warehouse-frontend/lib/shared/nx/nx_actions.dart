import 'package:flutter/widgets.dart';

import '../../core/error/app_error.dart';
import 'nx_overlays.dart';

/// The prototype's `toggleActive`: deactivating asks first ("hidden from
/// pickers, NOT deleted"), then toasts with an Undo; reactivating just does it.
/// [refresh] runs after every change (invalidate the list's providers).
Future<void> nxToggleActive(
  BuildContext context, {
  required String name,
  required bool active,
  required Future<void> Function() deactivate,
  required Future<void> Function() reactivate,
  required VoidCallback refresh,
}) async {
  if (active) {
    final ok = await showNxConfirm(
      context,
      title: 'Deactivate $name?',
      body: 'It is marked inactive and hidden from pickers. It is NOT deleted and stays visible in history.',
      confirmLabel: 'Deactivate',
      danger: true,
    );
    if (!ok) return;
  }
  try {
    if (active) {
      await deactivate();
    } else {
      await reactivate();
    }
    refresh();
    NxToast.ok(
      '$name ${active ? 'deactivated' : 'reactivated'}',
      active ? 'Kept in history — not deleted.' : null,
      active
          ? NxToastAction('Undo', () async {
              try {
                await reactivate();
                refresh();
              } on AppError catch (e) {
                NxToast.error('Could not undo', e.message);
              }
            })
          : null,
    );
  } on AppError catch (e) {
    NxToast.error('Not changed', e.message);
  }
}
