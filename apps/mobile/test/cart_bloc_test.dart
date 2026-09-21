import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/cart_bloc.dart';

void main() {
  const maize = PosProduct(
    id: 'maize',
    name: 'Maize Meal 2.5kg',
    priceMinor: 3800,
    availableQuantity: 2,
  );

  test('cart calculates totals with integer minor units', () async {
    final bloc = CartBloc();
    bloc.add(const CartProductAdded(maize));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const CartProductAdded(maize));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.itemCount, 2);
    expect(bloc.state.totalMinor, 7600);
    await bloc.close();
  });

  test('cart refuses quantity above known available stock', () async {
    final bloc = CartBloc();
    bloc.add(const CartProductAdded(maize));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const CartQuantityChanged(productId: 'maize', quantity: 3));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.itemCount, 1);
    await bloc.close();
  });

  test('payment method is event driven state', () async {
    final bloc = CartBloc();
    bloc.add(const CartPaymentMethodChanged(PaymentMethod.mobileMoney));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.paymentMethod, PaymentMethod.mobileMoney);
    await bloc.close();
  });
}
