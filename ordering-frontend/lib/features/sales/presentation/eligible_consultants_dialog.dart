import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../users/data/users_providers.dart';
import '../../users/domain/user.dart';
import '../data/sales_providers.dart';
import '../domain/sale_campaign_summary.dart';

/// Which consultants' customers may buy at a RESTRICTED campaign's price — this is the one piece
/// of a campaign ordering actually owns (the warehouse has no concept of a customer; see
/// ARCHITECTURE.md). Eligibility is assigned by consultant, not by individual customer: pick the
/// consultants here, and every customer assigned to one of them qualifies automatically.
Future<void> showEligibleConsultantsDialog(BuildContext context, SaleCampaignSummary campaign) =>
    showNxDialog<void>(context, width: 480, builder: (_) => _EligibleConsultantsDialog(campaign: campaign));

class _EligibleConsultantsDialog extends ConsumerStatefulWidget {
  const _EligibleConsultantsDialog({required this.campaign});

  final SaleCampaignSummary campaign;

  @override
  ConsumerState<_EligibleConsultantsDialog> createState() => _EligibleConsultantsDialogState();
}

class _EligibleConsultantsDialogState extends ConsumerState<_EligibleConsultantsDialog> {
  final _search = TextEditingController();
  Set<String>? _selected; // null until the current list has loaded
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(salesApiProvider).setEligible(widget.campaign.id, _selected!.toList());
      ref.invalidate(eligibleConsultantsProvider(widget.campaign.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      NxToast.ok(
        'Eligible consultants updated',
        '${_selected!.length} consultant(s) — and every customer assigned to them — can now buy ${widget.campaign.name} at its price.',
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
    final consultants = ref.watch(consultantsListProvider).value ?? const <ConsultantRef>[];
    final current = ref.watch(eligibleConsultantsProvider(widget.campaign.id));

    return current.when(
      loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => NxDialogFrame(
        title: 'Eligible consultants',
        body: Text(e is AppError ? e.message : 'Could not load the eligible-consultant list.', style: TextStyle(fontSize: 12, color: n.bad)),
        actions: [NxButton(label: 'Close', onPressed: () => Navigator.of(context).pop())],
      ),
      data: (rows) {
        _selected ??= {for (final r in rows) r.consultantId};
        final query = _search.text.trim().toLowerCase();
        final visible = query.isEmpty
            ? consultants
            : consultants.where((c) => c.fullName.toLowerCase().contains(query) || c.email.toLowerCase().contains(query)).toList();

        return NxDialogFrame(
          title: 'Eligible consultants',
          sub: '${widget.campaign.name} — every customer assigned to one of these consultants gets its sale price.',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxInput(controller: _search, placeholder: 'Search by name or email', onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              Text('${_selected!.length} selected', style: TextStyle(fontSize: 11, color: n.n500)),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 360),
                decoration: BoxDecoration(color: n.surface, borderRadius: BorderRadius.circular(NxRadius.md)),
                child: visible.isEmpty
                    ? Padding(padding: const EdgeInsets.all(14), child: Text('No consultants match.', style: TextStyle(fontSize: 12, color: n.n400)))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final c = visible[i];
                          final checked = _selected!.contains(c.id);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            onChanged: (v) => setState(() => v == true ? _selected!.add(c.id) : _selected!.remove(c.id)),
                            title: Text(c.fullName, style: TextStyle(fontSize: 13, color: n.text)),
                            subtitle: Text(c.email, style: TextStyle(fontSize: 11, color: n.n500)),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
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
            NxButton(label: 'Cancel', onPressed: _saving ? null : () => Navigator.of(context).pop()),
            NxButton.primary(label: _saving ? 'Saving…' : 'Save', onPressed: _saving ? null : _save),
          ],
        );
      },
    );
  }
}
