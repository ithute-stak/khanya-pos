/// Provider-neutral types for an eventual server-authorized mobile-money flow.
///
/// These client-side types are for displaying and querying collection status.
//// They are NOT payment authorization. Only the Khanya backend may verify
/// provider callbacks, bind payments to a sale, and authorize finalization.
enum MobileMoneyRail { mpesa, ecocash }

enum MobileMoneyCollectionStatus {
  awaitingCustomer,
  pendingProvider,
  confirmed,
  failed,
  cancelled,
  unknown,
}

class MobileMoneyCollectionRequest {
  const MobileMoneyCollectionRequest({
    required this.operationId,
    required this.tenantId,
    required this.branchId,
    required this.amountMinor,
    required this.currency,
    required this.rail,
  });

  /// Immutable, unique operation identifier created before provider initiation.
  final String operationId;
  final String tenantId;
  final String branchId;
  final int amountMinor;
  final String currency;
  final MobileMoneyRail rail;

  void validate() {
    if (operationId.trim().isEmpty ||
        tenantId.trim().isEmpty ||
        branchId.trim().isEmpty ||
        amountMinor <= 0 ||
        currency != 'LSL') {
      throw ArgumentError('A valid LSL collection needs a merchant, branch, '
          'operation identifier, and positive amount.');
    }
  }
}

/// Read-only status returned by a trusted backend API.
///
/// Never trust this object when submitted *by the POS client* as proof of
/// payment. The backend must independently check it with the provider.
class MobileMoneyCollectionStatusSnapshot {
  const MobileMoneyCollectionStatusSnapshot({
    required this.operationId,
    required this.tenantId,
    required this.branchId,
    required this.amountMinor,
    required this.currency,
    required this.rail,
    required this.status,
    this.providerReference,
  });

  final String operationId;
  final String tenantId;
  final String branchId;
  final int amountMinor;
  final String currency;
  final MobileMoneyRail rail;
  final MobileMoneyCollectionStatus status;
  final String? providerReference;

  /// Checks that the response describes the exact requested collection.
  /// This is an integrity check, not a substitute for backend authorization.
  bool matches(MobileMoneyCollectionRequest request) {
    return operationId == request.operationId &&
        tenantId == request.tenantId &&
        branchId == request.branchId &&
        amountMinor == request.amountMinor &&
        currency == request.currency &&
        rail == request.rail;
  }

  bool confirmedForDisplay(MobileMoneyCollectionRequest request) =>
      status == MobileMoneyCollectionStatus.confirmed &&
      matches(request) &&
      providerReference != null &&
      providerReference!.trim().isNotEmpty;
}

/// Implementations must call an authorized backend, never send direct provider
/// credentials from a POS device. They must reuse the same operationId on
/// retries and query the original collection after an uncertain response.
abstract class MobileMoneyCollectionGateway {
  Future<MobileMoneyCollectionStatusSnapshot> initiate(
    MobileMoneyCollectionRequest request,
  );

  Future<MobileMoneyCollectionStatusSnapshot> lookup(
    MobileMoneyCollectionRequest request,
  );
}
