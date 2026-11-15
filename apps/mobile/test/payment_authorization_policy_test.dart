import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/domain/payment_authorization_policy.dart';

void main() {
  group('mobile-money checkout authorization', () {
    test('blocks unverified M-Pesa/EcoCash payment before recording a sale', () {
      expect(
        () => PaymentAuthorizationPolicy.requireCheckoutReady(
          method: PaymentMethod.mobileMoney,
          immediatePaymentMinor: 12500,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('does not treat a fully credit-funded sale as a mobile payment', () {
      expect(
        () => PaymentAuthorizationPolicy.requireCheckoutReady(
          method: PaymentMethod.mobileMoney,
          immediatePaymentMinor: 0,
        ),
        returnsNormally,
      );
    });

    test('keeps existing cash, card and bank transfer paths unchanged', () {
      for (final method in [
        PaymentMethod.cash,
        PaymentMethod.card,
        PaymentMethod.bankTransfer,
      ]) {
        expect(
          () => PaymentAuthorizationPolicy.requireCheckoutReady(
            method: method,
            immediatePaymentMinor: 12500,
          ),
          returnsNormally,
        );
      }
    });

    test('only a positive mobile collection requires provider confirmation', () {
      expect(
        PaymentAuthorizationPolicy.requiresVerifiedCollection(
          method: PaymentMethod.mobileMoney,
          immediatePaymentMinor: 1,
        ),
        isTrue,
      );
      expect(
        PaymentAuthorizationPolicy.requiresVerifiedCollection(
          method: PaymentMethod.cash,
          immediatePaymentMinor: 1,
        ),
        isFalse,
      );
    });
  });
}
