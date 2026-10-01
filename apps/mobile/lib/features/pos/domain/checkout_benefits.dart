class CheckoutBenefitsSelection {
  const CheckoutBenefitsSelection({
    required this.subtotalMinor,
    required this.totalMinor,
    required this.discountMinor,
    required this.customerId,
    this.promotionCode,
    this.loyaltyPointsToRedeem = 0,
  });

  final int subtotalMinor;
  final int totalMinor;
  final int discountMinor;
  final String? customerId;
  final String? promotionCode;
  final int loyaltyPointsToRedeem;

  bool matches({required int subtotalMinor, required String? customerId}) =>
      this.subtotalMinor == subtotalMinor && this.customerId == customerId;
}

class CheckoutBenefitsStore {
  CheckoutBenefitsStore._();

  static CheckoutBenefitsSelection? _selection;

  static CheckoutBenefitsSelection? get current => _selection;

  static CheckoutBenefitsSelection? validFor({
    required int subtotalMinor,
    required String? customerId,
  }) {
    final selection = _selection;
    if (selection == null || !selection.matches(subtotalMinor: subtotalMinor, customerId: customerId)) {
      return null;
    }
    return selection;
  }

  static void apply(CheckoutBenefitsSelection selection) {
    _selection = selection;
  }

  static void clear() {
    _selection = null;
  }
}
