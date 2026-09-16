/// Mirrors the backend's `ProductStatus` Prisma enum exactly (`ACTIVE` /
/// `INACTIVE`) — soft-delete only, a product is never hard-deleted.
enum ProductStatus {
  active,
  inactive;

  static ProductStatus fromJson(String value) => switch (value) {
    'ACTIVE' => ProductStatus.active,
    'INACTIVE' => ProductStatus.inactive,
    _ => throw ArgumentError('Unknown product status: $value'),
  };

  String toJson() => switch (this) {
    ProductStatus.active => 'ACTIVE',
    ProductStatus.inactive => 'INACTIVE',
  };

  String get label => switch (this) {
    ProductStatus.active => 'Active',
    ProductStatus.inactive => 'Inactive',
  };
}
