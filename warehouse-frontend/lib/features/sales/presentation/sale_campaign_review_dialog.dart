import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/sales_providers.dart';
import '../domain/sale_campaign.dart';
import 'sale_campaign_form_dialog.dart';

enum _Action { approve, reject, cancel }

String campaignDiscount(SaleCampaignProduct p) => switch (p.discountType) {
  SaleDiscountType.percent => '${fmtPlain(p.discountValue)}% off',
  SaleDiscountType.fixedAmount => '${fmtMoney(p.discountValue)} off',
  SaleDiscountType.fixedPrice => '${fmtMoney(p.discountValue)} flat',
};

Tone campaignStatusTone(SaleCampaignStatus s) => switch (s) {
  SaleCampaignStatus.pendingApproval => Tone.warn,
  SaleCampaignStatus.scheduled => Tone.info,
  SaleCampaignStatus.active => Tone.ok,
  SaleCampaignStatus.ended => Tone.neutral,
  SaleCampaignStatus.rejected || SaleCampaignStatus.cancelled => Tone.bad,
};

class _Summary extends StatelessWidget {
  const _Summary(this.c);

  final SaleCampaign c;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(NxRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text)),
          Text(
            '${fmtDateTime(c.startsAt.toLocal())} → ${fmtDateTime(c.endsAt.toLocal())} · ${c.eligibility.label}'
            '${c.isDailyWindow ? ' · live ${fmtTime(c.dailyWindowStartLocal)}–${fmtTime(c.dailyWindowEndLocal)} daily' : ''}'
            '${c.maxUsesPerCustomer == null ? '' : ' · max ${c.maxUsesPerCustomer} per customer'}',
            style: TextStyle(fontSize: 12, color: n.n400),
          ),
          const SizedBox(height: 8),
          for (final p in c.products)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${p.product.sku} ${p.product.name} — ${campaignDiscount(p)} (${fmtMoney(p.product.sellingPrice)} → ${fmtMoney(p.previewPrice)}${p.minQuantity > 1 ? ', min ${fmtNum(p.minQuantity)}' : ''})',
                style: TextStyle(fontSize: 12, color: n.n300),
              ),
            ),
        ],
      ),
    );
  }
}

/// Approve / reject / cancel (mirrors the Stock Adjustments review dialog). Approving makes the
/// campaign SCHEDULED (or immediately ACTIVE if its start has already passed); rejecting/cancelling
/// never change any price. Confirmed with a one-time code automatically (OtpInterceptor).
Future<void> showSaleCampaignReview(BuildContext context, SaleCampaign c, {required String action}) =>
    showNxDialog<void>(context, builder: (_) => _Review(c: c, action: switch (action) { 'approve' => _Action.approve, 'reject' => _Action.reject, _ => _Action.cancel }));

class _Review extends ConsumerStatefulWidget {
  const _Review({required this.c, required this.action});

  final SaleCampaign c;
  final _Action action;

  @override
  ConsumerState<_Review> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<_Review> {
  final _note = TextEditingController();
  bool _noteErr = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final note = _note.text.trim();
    if (widget.action == _Action.reject && note.isEmpty) {
      setState(() => _noteErr = true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(salesApiProvider);
      switch (widget.action) {
        case _Action.approve:
          await api.approve(widget.c.id, reviewNote: note.isEmpty ? null : note);
        case _Action.reject:
          await api.reject(widget.c.id, reviewNote: note);
        case _Action.cancel:
          await api.cancel(widget.c.id, reviewNote: note.isEmpty ? null : note);
      }
      ref.invalidate(salesListProvider);
      if (mounted) Navigator.of(context).pop();
      final verb = switch (widget.action) { _Action.approve => 'approved', _Action.reject => 'rejected', _Action.cancel => 'cancelled' };
      NxToast.ok('Sale campaign $verb', widget.c.name);
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final title = switch (widget.action) { _Action.approve => 'Approve campaign', _Action.reject => 'Reject campaign', _Action.cancel => 'Cancel campaign' };
    final color = widget.action == _Action.approve ? n.accent : n.bad;
    final explain = switch (widget.action) {
      _Action.approve => 'Goes live on schedule (or immediately, if the start time has already passed).',
      _Action.reject => 'This campaign will never go live. No price changes.',
      _Action.cancel => 'Ends the campaign early — pricing reverts right away.',
    };
    return NxDialogFrame(
      title: title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(widget.c),
          const SizedBox(height: 10),
          Text(explain, style: TextStyle(fontSize: 12, color: n.n400)),
          const SizedBox(height: 10),
          NxField(
            label: widget.action == _Action.reject ? 'Review note (required)' : 'Review note (optional)',
            error: _noteErr ? 'Add a note so the requester knows why.' : null,
            child: NxInput(
              controller: _note,
              maxLines: 4,
              minLines: 3,
              error: _noteErr,
              autofocus: true,
              onChanged: (_) {
                if (_noteErr) setState(() => _noteErr = false);
              },
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)),
          ],
        ],
      ),
      actions: [
        NxButton(label: 'Back', onPressed: _saving ? null : () => Navigator.of(context).pop()),
        NxButton(label: _saving ? 'Saving…' : title, color: color, onPressed: _saving ? null : _submit),
      ],
    );
  }
}

/// Everything about one campaign (opened from the list).
Future<void> showSaleCampaignDetail(BuildContext context, SaleCampaign c) =>
    showNxDialog<void>(context, width: 560, builder: (_) => _Detail(c: c));

class _Detail extends ConsumerWidget {
  const _Detail({required this.c});

  final SaleCampaign c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canApprove = user?.can('sales.approve') ?? false;
    final canSchedule = user?.can('sales.schedule') ?? false;
    final own = user?.id == c.requestedBy;
    Widget fact(String l, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(l, style: TextStyle(fontSize: 12, color: n.n500))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 13, color: n.text))),
        ],
      ),
    );
    return NxDialogFrame(
      title: 'Sale campaign',
      titleWidget: Row(
        children: [
          Expanded(child: Text(c.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: n.text))),
          NxTag(c.status.label, tone: campaignStatusTone(c.status)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(c),
          const SizedBox(height: 12),
          fact('Requested', '${c.requestedByUser.fullName} · ${fmtDateTime(c.requestedAt.toLocal())}'),
          if (c.reviewedByUser != null) fact('Reviewed', '${c.reviewedByUser!.fullName} · ${fmtDateTime(c.reviewedAt!.toLocal())}'),
          if ((c.reviewNote ?? '').isNotEmpty) fact('Review note', '“${c.reviewNote}”'),
          if (c.status.isPending && own) ...[
            const SizedBox(height: 6),
            Text('This is your request — another reviewer must approve it.', style: TextStyle(fontSize: 12, color: n.n400)),
          ],
        ],
      ),
      actions: [
        NxButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        if (c.status.canEdit && own && canSchedule)
          NxButton(
            label: 'Edit',
            icon: PhosphorIconsRegular.pencilSimple,
            onPressed: () {
              Navigator.of(context).pop();
              showSaleCampaignEditForm(context, c);
            },
          ),
        if (c.status.canReopen && canSchedule)
          NxButton(
            label: 'Reopen',
            icon: PhosphorIconsRegular.arrowCounterClockwise,
            onPressed: () {
              Navigator.of(context).pop();
              showSaleCampaignReopenForm(context, c);
            },
          ),
        if (c.status.isPending && canApprove && !own) ...[
          NxButton(
            label: 'Reject',
            icon: PhosphorIconsRegular.x,
            color: n.bad,
            onPressed: () {
              Navigator.of(context).pop();
              showSaleCampaignReview(context, c, action: 'reject');
            },
          ),
          NxButton.primary(
            label: 'Approve',
            icon: PhosphorIconsRegular.check,
            onPressed: () {
              Navigator.of(context).pop();
              showSaleCampaignReview(context, c, action: 'approve');
            },
          ),
        ],
        if (c.status.canCancel && canApprove)
          NxButton(
            label: 'Cancel campaign',
            icon: PhosphorIconsRegular.prohibit,
            color: n.bad,
            onPressed: () {
              Navigator.of(context).pop();
              showSaleCampaignReview(context, c, action: 'cancel');
            },
          ),
      ],
    );
  }
}
