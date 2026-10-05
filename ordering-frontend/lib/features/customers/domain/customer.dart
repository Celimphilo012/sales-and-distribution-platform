/// Mirrors the backend's `customers.status` enum (`ordering-backend/db/schema.sql`)
/// — two states only (unlike `UserStatus`'s three). `DELETE /customers/:id`
/// always lands on INACTIVE (soft-delete, rule 10); `PATCH` can also set
/// `status` directly, which is how a deactivated customer gets reactivated.
enum CustomerStatus { active, inactive }

CustomerStatus customerStatusFromJson(String value) => switch (value) {
  'ACTIVE' => CustomerStatus.active,
  'INACTIVE' => CustomerStatus.inactive,
  _ => throw ArgumentError('Unknown customer status: $value'),
};

extension CustomerStatusX on CustomerStatus {
  String get apiValue => this == CustomerStatus.active ? 'ACTIVE' : 'INACTIVE';
  String get label => this == CustomerStatus.active ? 'Active' : 'Inactive';
}

/// Mirrors `GET/POST/PATCH/DELETE /customers` (`CustomersService`) —
/// field names match the API's camelCase JSON exactly, per ARCHITECTURE.md
/// §E's `customers` table (`name, phone, address, location_text, status,
/// notes`). Customers live entirely in the ordering system — no
/// warehouse/cross-system fields here. The backend's `Customer` model has an
/// `orders` relation, but neither `findAll` nor `findOne` includes it (no
/// order history comes back from this API) — that's wired up in R3.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.locationText,
    required this.status,
    this.notes,
    this.assignedConsultantId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? locationText;
  final CustomerStatus status;
  final String? notes;

  /// Which consultant this customer belongs to — drives RESTRICTED sale-campaign eligibility
  /// (a campaign is opened to consultants; every customer assigned to an eligible one qualifies).
  final String? assignedConsultantId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    locationText: json['locationText'] as String?,
    status: customerStatusFromJson(json['status'] as String),
    notes: json['notes'] as String?,
    assignedConsultantId: json['assignedConsultantId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
