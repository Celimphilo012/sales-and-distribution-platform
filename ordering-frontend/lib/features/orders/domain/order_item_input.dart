/// What `POST`/`PATCH /orders` send per line — mirrors the real
/// `OrderItemInputDto` EXACTLY: `productId` + `quantity` only. There is
/// deliberately no `price`/`name` field here — the server snapshots both
/// from the warehouse catalogue (rule 8). The backend's global
/// `ValidationPipe` also runs with `forbidNonWhitelisted: true`, so a
/// client that tried to send an extra `price` field would get a 400, not
/// have it silently accepted or ignored.
class OrderItemInput {
  const OrderItemInput({required this.productId, required this.quantity});

  final String productId;
  final double quantity;

  Map<String, dynamic> toJson() => {'productId': productId, 'quantity': quantity};
}
