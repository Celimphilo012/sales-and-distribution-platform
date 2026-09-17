import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// A labeled, checkbox-driven multi-select list, generic over the option
/// type [T]. Optionally grouped under section headers via [groupOf] (e.g.
/// permissions grouped by module) — pass `null` for a flat list (e.g. a
/// user's role assignment). Pairs with [AppDropdownField]/[AppTextField] as
/// the multi-value counterpart in RBAC-style forms (roles ↔ permissions,
/// users ↔ roles) — the shape both `/warehouse-frontend` and, later, the
/// ordering app's near-identical admin screens need.
class AppMultiSelectList<T> extends StatelessWidget {
  const AppMultiSelectList({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.idOf,
    required this.labelOf,
    this.subtitleOf,
    this.groupOf,
    required this.onToggle,
  });

  final List<T> items;
  final Set<String> selectedIds;
  final String Function(T) idOf;
  final String Function(T) labelOf;
  final String? Function(T)? subtitleOf;

  /// Section header per distinct group; items with a `null` group are
  /// grouped last under "Other". Leave `null` for an ungrouped, flat list.
  final String? Function(T)? groupOf;

  final void Function(T item, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    if (groupOf == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [for (final item in items) _tile(item)]);
    }

    final grouped = <String, List<T>>{};
    for (final item in items) {
      final group = groupOf!(item) ?? 'Other';
      grouped.putIfAbsent(group, () => []).add(item);
    }
    final groupNames = grouped.keys.toList()..sort();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groupNames) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
            child: Text(
              group,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          for (final item in grouped[group]!) _tile(item),
        ],
      ],
    );
  }

  Widget _tile(T item) {
    final id = idOf(item);
    final subtitleText = subtitleOf?.call(item);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(labelOf(item)),
      subtitle: subtitleText != null && subtitleText.isNotEmpty ? Text(subtitleText) : null,
      value: selectedIds.contains(id),
      onChanged: (checked) => onToggle(item, checked ?? false),
    );
  }
}
