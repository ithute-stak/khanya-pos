import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';

sealed class CartEvent extends Equatable {
  const CartEvent();

  @override
  List<Object?> get props => [];
}

final class CartProductAdded extends CartEvent {
  const CartProductAdded(this.product);
  final PosProduct product;

  @override
  List<Object?> get props => [product];
}

final class CartQuantityChanged extends CartEvent {
  const CartQuantityChanged({required this.productId, required this.quantity});
  final String productId;
  final int quantity;

  @override
  List<Object?> get props => [productId, quantity];
}

final class CartProductRemoved extends CartEvent {
  const CartProductRemoved(this.productId);
  final String productId;

  @override
  List<Object?> get props => [productId];
}

final class CartCleared extends CartEvent {
  const CartCleared();
}

class CartState extends Equatable {
  const CartState({this.lines = const []});

  final List<CartLine> lines;

  int get totalMinor => lines.fold(0, (total, line) => total + line.lineTotalMinor);
  int get itemCount => lines.fold(0, (total, line) => total + line.quantity);

  @override
  List<Object?> get props => [lines];
}

class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc() : super(const CartState()) {
    on<CartProductAdded>((event, emit) {
      final lines = [...state.lines];
      final index = lines.indexWhere((line) => line.product.id == event.product.id);
      if (index == -1) {
        lines.add(CartLine(product: event.product, quantity: 1));
      } else {
        final nextQuantity = lines[index].quantity + 1;
        if (event.product.availableQuantity != null && nextQuantity > event.product.availableQuantity!) {
          return;
        }
        lines[index] = lines[index].copyWith(quantity: nextQuantity);
      }
      emit(CartState(lines: List.unmodifiable(lines)));
    });

    on<CartQuantityChanged>((event, emit) {
      final lines = [...state.lines];
      final index = lines.indexWhere((line) => line.product.id == event.productId);
      if (index == -1) return;
      if (event.quantity <= 0) {
        lines.removeAt(index);
      } else {
        final available = lines[index].product.availableQuantity;
        if (available != null && event.quantity > available) return;
        lines[index] = lines[index].copyWith(quantity: event.quantity);
      }
      emit(CartState(lines: List.unmodifiable(lines)));
    });

    on<CartProductRemoved>((event, emit) {
      emit(CartState(lines: state.lines.where((line) => line.product.id != event.productId).toList(growable: false)));
    });

    on<CartCleared>((event, emit) => emit(const CartState()));
  }
}
