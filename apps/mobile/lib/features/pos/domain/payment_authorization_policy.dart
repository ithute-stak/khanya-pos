import 'package:khanya_pos/features/pos/domain/cart.dart';

/// Fail-closed rule for provider-initiated mobile-money checkout.
///
/// Selecting a payment label or receiving an SMS is NOT proof that the
/// merchant's M-Pesa/EcoCash collection was settled. Khanya must not create
/// a paid sale or queue an offline-paid sale until the backend verifies an
/// authenticated, amount-bound provider collection for this operation.
///
/// Cash, card and bank-transfer methods retain their existing behavior.
/// A provider adapter and authoritative verification endpoint are required
/// before mobile money can be enabled.
abstract final class PaymentAuthorizationPolicy {
  static bool requiresVerifiedCollection({
    required PaymentMethod method,
    required int immediatePaymentMinor,
  }) => method == PaymentMethod.mobileMoney && immediatePaymentMinor > 0;

  static void requireCheckoutReady({
    required PaymentMethod method,
    required int immediatePaymentMinor,
  }) {
    if (requiresVerifiedCollection(
      method: method,
      immediatePaymentMinor: immediatePaymentMinor,
    )) {
      throw StateError(
        'Mobile money payment verification is not configured. '
        'Do not record M-Pesa or EcoCash as paid until Khanya confirms '
        'the payment with the provider. Select an already supported '
        'payment method instead.',
      );
    }
  }
}
