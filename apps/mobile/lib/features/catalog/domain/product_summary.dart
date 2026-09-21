import 'package:equatable/equatable.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';

class ProductSummary extends Equatable {
  const ProductSummary({
    required this.id,
    required this.name,
    required this.sku,
    required this.unit,
    required this.sellingPriceMinor,
    required this.costPriceMinor,
    required this.reorderLevelMilli,
    required this.tracksStock,
    required this.isLowStock,
    this.barcode,
    this.categoryId,
    this.onHandMilli,
  });

  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String unit;
  final int sellingPriceMinor;
  final int costPriceMinor;
  final int? onHandMilli;
  final int reorderLevelMilli;
  final bool tracksStock;
  final bool isLowStock;

  int? get availableWholeUnits => onHandMilli == null ? null : onHandMilli! ~/ 1000;

  PosProduct toPosProduct() => PosProduct(
        id: id,
        name: name,
        priceMinor: sellingPriceMinor,
        sku: sku,
        availableQuantity: tracksStock ? availableWholeUnits : null,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        sku,
        barcode,
        categoryId,
        unit,
        sellingPriceMinor,
        costPriceMinor,
        onHandMilli,
        reorderLevelMilli,
        tracksStock,
        isLowStock,
      ];
}
