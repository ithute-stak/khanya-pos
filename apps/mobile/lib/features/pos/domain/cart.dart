import 'package:equatable/equatable.dart';

enum PaymentMethod {
  cash('cash', 'Cash'),
  card('card', 'Card'),
  mobileMoney('mobile_money', 'Mobile money'),
  bankTransfer('bank_transfer', 'Bank transfer');

  const PaymentMethod(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class PosProduct extends Equatable {
  const PosProduct({
    required this.id,
    required this.name,
    required this.priceMinor,
    this.sku,
    this.availableQuantity,
  });

  final String id;
  final String name;
  final int priceMinor;
  final String? sku;
  final int? availableQuantity;

  @override
  List<Object?> get props => [id, name, priceMinor, sku, availableQuantity];
}

class CartLine extends Equatable {
  const CartLine({required this.product, required this.quantity});

  final PosProduct product;
  final int quantity;

  int get lineTotalMinor => product.priceMinor * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        product: product,
        quantity: quantity ?? this.quantity,
      );

  @override
  List<Object?> get props => [product, quantity];
}
