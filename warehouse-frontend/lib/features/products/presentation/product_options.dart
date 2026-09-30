import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../domain/product.dart';
import '../domain/product_status.dart';

/// Products as searchable picker options — "SKU — Name", matched on SKU,
/// name and category, with total on hand on the right. Inactive products are
/// left out unless [includeInactive] (or unless one is [keepId], the current
/// value, so an existing selection never disappears).
List<NxOption<String>> productOptions(List<Product> products, {bool includeInactive = false, String? keepId}) {
  final list = [
    for (final p in products)
      if (includeInactive || p.status == ProductStatus.active || p.id == keepId)
        NxOption(
          p.id,
          '${p.sku} — ${p.name}',
          sub: [p.category?.name, if (p.status != ProductStatus.active) 'inactive'].whereType<String>().join(' · '),
          search: p.category?.parent?.name,
          trailing: '${fmtNum(p.totalOnHand)} ${p.uom}',
        ),
  ];
  list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return list;
}
