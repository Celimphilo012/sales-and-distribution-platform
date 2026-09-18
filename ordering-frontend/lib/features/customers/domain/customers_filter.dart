/// Filter state for `GET /customers`, mirroring `ListCustomersQueryDto`
/// field-for-field. The real API has NO pagination and NO tri-state status
/// filter — just a boolean `includeInactive` (default false = active only)
/// plus a `search` matched case-insensitively against name OR phone
/// server-side. `statusFilter` here is a client-side convenience: "Active"
/// sends `includeInactive: false`; "All" sends `includeInactive: true`, and
/// "Inactive only" filters the "All" result down client-side, since the API
/// has no way to ask for inactive-only directly.
enum CustomerStatusFilter { active, all, inactiveOnly }

extension CustomerStatusFilterX on CustomerStatusFilter {
  String get label => switch (this) {
    CustomerStatusFilter.active => 'Active',
    CustomerStatusFilter.all => 'All',
    CustomerStatusFilter.inactiveOnly => 'Inactive only',
  };
}

class CustomersFilter {
  const CustomersFilter({this.search, this.statusFilter = CustomerStatusFilter.active});

  final String? search;
  final CustomerStatusFilter statusFilter;

  bool get includeInactive => statusFilter != CustomerStatusFilter.active;

  CustomersFilter copyWith({String? search, bool clearSearch = false, CustomerStatusFilter? statusFilter}) {
    return CustomersFilter(
      search: clearSearch ? null : (search ?? this.search),
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    final trimmed = search?.trim();
    return {'search': ?(trimmed == null || trimmed.isEmpty ? null : trimmed), 'includeInactive': includeInactive};
  }

  @override
  bool operator ==(Object other) =>
      other is CustomersFilter && other.search == search && other.statusFilter == statusFilter;

  @override
  int get hashCode => Object.hash(search, statusFilter);
}
