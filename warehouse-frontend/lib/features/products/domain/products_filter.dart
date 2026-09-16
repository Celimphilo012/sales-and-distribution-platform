import 'product_status.dart';

/// UI-facing status filter for the products list — a third "all" option
/// beyond the two real [ProductStatus] values the backend knows about.
/// Translated to `status`/`includeInactive` query params by [ProductsFilter].
enum ProductStatusFilter {
  active,
  inactive,
  all;

  String get label => switch (this) {
    ProductStatusFilter.active => 'Active',
    ProductStatusFilter.inactive => 'Inactive',
    ProductStatusFilter.all => 'All',
  };
}

const _unset = Object();

/// Mirrors the real query params `GET /products` accepts
/// (`ListProductsQueryDto`): `search`, `categoryId`, `status`,
/// `includeInactive` (`status` overrides `includeInactive` server-side).
/// There is no pagination param on this endpoint (confirmed against the
/// real `ListProductsQueryDto`).
class ProductsFilter {
  const ProductsFilter({this.search, this.categoryId, this.status, this.includeInactive = false});

  final String? search;
  final String? categoryId;
  final ProductStatus? status;
  final bool includeInactive;

  /// The default (`status: null, includeInactive: false`) means "active
  /// only" — same as what the backend defaults to when no params are sent
  /// — not "all". Only an explicit `includeInactive: true` means "all".
  ProductStatusFilter get statusFilter {
    if (status == ProductStatus.active) return ProductStatusFilter.active;
    if (status == ProductStatus.inactive) return ProductStatusFilter.inactive;
    return includeInactive ? ProductStatusFilter.all : ProductStatusFilter.active;
  }

  ProductsFilter copyWith({
    Object? search = _unset,
    Object? categoryId = _unset,
    ProductStatusFilter? statusFilter,
  }) {
    var newStatus = status;
    var newIncludeInactive = includeInactive;
    switch (statusFilter) {
      case ProductStatusFilter.active:
        newStatus = ProductStatus.active;
        newIncludeInactive = false;
      case ProductStatusFilter.inactive:
        newStatus = ProductStatus.inactive;
        newIncludeInactive = false;
      case ProductStatusFilter.all:
        newStatus = null;
        newIncludeInactive = true;
      case null:
        break;
    }
    return ProductsFilter(
      search: identical(search, _unset) ? this.search : search as String?,
      categoryId: identical(categoryId, _unset) ? this.categoryId : categoryId as String?,
      status: newStatus,
      includeInactive: newIncludeInactive,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    final trimmedSearch = search?.trim();
    return {
      if (trimmedSearch != null && trimmedSearch.isNotEmpty) 'search': trimmedSearch,
      if (categoryId != null) 'categoryId': categoryId,
      if (status != null) 'status': status!.toJson() else if (includeInactive) 'includeInactive': true,
    };
  }
}
