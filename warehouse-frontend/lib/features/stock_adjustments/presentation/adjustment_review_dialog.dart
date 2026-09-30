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
import '../../inventory/data/inventory_providers.dart';
import '../data/stock_adjustments_providers.dart';
import '../domain/stock_adjustment.dart';

String adjustmentDelta(StockAdjustment a) => '${a.direction == AdjustmentDirection.increase ? '+' : '−'}${fmtNum(a.delta)}';

/// The evidence photo attached to a request — a thumbnail that opens full size.
class AdjustmentPhoto extends ConsumerWidget {
  const AdjustmentPhoto({super.key, required this.adjustmentId, this.size = 72});

  final String adjustmentId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final bytes = ref.watch(adjustmentPhotoProvider(adjustmentId));
    return bytes.when(
      loading: () => SizedBox(width: size, height: size, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Text('Photo could not be loaded', style: TextStyle(fontSize: 12, color: n.n400)),
      data: (data) => InkWell(
        onTap: () => showNxDialog<void>(
          context,
          width: 720,
          builder: (ctx) => NxDialogFrame(
            title: 'Evidence photo',
            body: ClipRRect(borderRadius: BorderRadius.circular(NxRadius.md), child: Image.memory(data, fit: BoxFit.contain)),
            actions: [NxButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop())],
          ),
        ),
        borderRadius: BorderRadius.circular(NxRadius.md),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NxRadius.md),
          child: Image.memory(data, width: size, height: size, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// A request's summary block: the change, product, bucket · location · who.
class _Summary extends StatelessWidget {
  const _Summary(this.a);

  final StockAdjustment a;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final inc = a.direction == AdjustmentDirection.increase;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(NxRadius.md)),
      child: Row(
        children: [
          Text(adjustmentDelta(a), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: inc ? n.ok : n.bad, fontFeatures: tabular)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.product.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text)),
                Text(
                  '${a.bucket.label.toLowerCase()} · ${a.location.code} · by ${a.requestedByUser.fullName}',
                  style: TextStyle(fontSize: 12, color: n.n400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Approve / reject (the prototype's review dialog). A rejection needs a
/// note; an approval moves stock immediately. The evidence photo, when there
/// is one, is right here where the decision is made.
Future<void> showAdjustmentReview(BuildContext context, StockAdjustment a, {required bool approve}) =>
    showNxDialog<void>(context, builder: (_) => _Review(a: a, approve: approve));

class _Review extends ConsumerStatefulWidget {
  const _Review({required this.a, required this.approve});

  final StockAdjustment a;
  final bool approve;

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
    if (!widget.approve && note.isEmpty) {
      setState(() => _noteErr = true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(stockAdjustmentsApiProvider);
      widget.approve
          ? await api.approve(widget.a.id, reviewNote: note.isEmpty ? null : note)
          : await api.reject(widget.a.id, reviewNote: note);
      ref.invalidate(stockAdjustmentsListProvider);
      if (widget.approve) invalidateStockViews(ref);
      if (mounted) Navigator.of(context).pop();
      NxToast.ok(
        widget.approve ? 'Adjustment approved' : 'Adjustment rejected',
        '${adjustmentDelta(widget.a)} ${widget.a.product.name}${widget.approve ? ' — stock moved' : ''}',
      );
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final a = widget.a;
    final color = widget.approve ? n.accent : n.bad;
    return NxDialogFrame(
      title: widget.approve ? 'Approve adjustment' : 'Reject adjustment',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(a),
          const SizedBox(height: 10),
          Text('“${a.reason}”', style: TextStyle(fontSize: 12, color: n.n300)),
          if (a.hasPhoto) ...[
            const SizedBox(height: 10),
            Row(children: [AdjustmentPhoto(adjustmentId: a.id), const SizedBox(width: 10), Text('Tap to enlarge', style: TextStyle(fontSize: 11, color: n.n500))]),
          ],
          const SizedBox(height: 10),
          Text(
            widget.approve ? 'Stock moves immediately when you approve.' : 'No stock moves. The requester sees your note.',
            style: TextStyle(fontSize: 12, color: n.n400),
          ),
          const SizedBox(height: 10),
          NxField(
            label: widget.approve ? 'Review note (optional)' : 'Review note (required)',
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
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton(
          label: _saving ? 'Saving…' : (widget.approve ? 'Approve' : 'Reject'),
          color: color,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

/// Everything about one request (opened from the list): the change, reason,
/// reference, photo, who asked and — once decided — who reviewed and why.
Future<void> showAdjustmentDetail(BuildContext context, StockAdjustment a) =>
    showNxDialog<void>(context, width: 560, builder: (_) => _Detail(a: a));

class _Detail extends ConsumerWidget {
  const _Detail({required this.a});

  final StockAdjustment a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canApprove = user?.can('inventory.adjust.approve') ?? false;
    final own = user?.id == a.requestedBy;
    final pending = a.status == AdjustmentStatus.pending;
    Widget fact(String l, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(l, style: TextStyle(fontSize: 12, color: n.n500))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 13, color: n.text))),
        ],
      ),
    );
    return NxDialogFrame(
      title: 'Adjustment',
      titleWidget: Row(
        children: [
          Expanded(child: Text('Adjustment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: n.text))),
          NxTag(a.status.label, tone: switch (a.status) {
            AdjustmentStatus.pending => Tone.warn,
            AdjustmentStatus.approved => Tone.ok,
            AdjustmentStatus.rejected => Tone.bad,
          }),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(a),
          const SizedBox(height: 12),
          fact('Reason', '“${a.reason}”'),
          if ((a.reference ?? '').isNotEmpty) fact('Reference', a.reference!),
          fact('Location', '${a.location.code} — ${a.location.name}'),
          fact('Requested', '${a.requestedByUser.fullName} · ${fmtDateTime(a.requestedAt)}'),
          if (a.reviewedByUser != null) fact('Reviewed', '${a.reviewedByUser!.fullName} · ${fmtDateTime(a.reviewedAt)}'),
          if ((a.reviewNote ?? '').isNotEmpty) fact('Review note', '“${a.reviewNote}”'),
          if (a.hasPhoto) ...[
            const SizedBox(height: 4),
            Text('Photo', style: TextStyle(fontSize: 12, color: n.n500)),
            const SizedBox(height: 6),
            AdjustmentPhoto(adjustmentId: a.id, size: 120),
          ],
          if (pending && own) ...[
            const SizedBox(height: 10),
            Text('This is your request — another reviewer must approve it.', style: TextStyle(fontSize: 12, color: n.n400)),
          ],
        ],
      ),
      actions: [
        NxButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        if (pending && canApprove && !own) ...[
          NxButton(
            label: 'Reject',
            icon: PhosphorIconsRegular.x,
            color: n.bad,
            onPressed: () {
              Navigator.of(context).pop();
              showAdjustmentReview(context, a, approve: false);
            },
          ),
          NxButton.primary(
            label: 'Approve',
            icon: PhosphorIconsRegular.check,
            onPressed: () {
              Navigator.of(context).pop();
              showAdjustmentReview(context, a, approve: true);
            },
          ),
        ],
      ],
    );
  }
}
