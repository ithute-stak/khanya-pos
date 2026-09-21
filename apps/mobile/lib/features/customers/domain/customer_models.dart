import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class CustomerSummary extends Equatable {
  const CustomerSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.creditLimitMinor,
    required this.paymentTermsDays,
    required this.outstandingMinor,
    required this.availableCreditMinor,
    required this.isActive,
    this.phone,
    this.email,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) => CustomerSummary(
        id: json['id'].toString(),
        code: json['code'].toString(),
        name: json['name'].toString(),
        phone: json['phone']?.toString(),
        email: json['email']?.toString(),
        creditLimitMinor: ScaledDecimal.toMinor(json['credit_limit'] ?? 0),
        paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt() ?? 0,
        outstandingMinor: ScaledDecimal.toMinor(json['outstanding_balance'] ?? 0),
        availableCreditMinor: ScaledDecimal.toMinor(json['available_credit'] ?? 0),
        isActive: json['is_active'] as bool? ?? true,
      );

  final String id;
  final String code;
  final String name;
  final String? phone;
  final String? email;
  final int creditLimitMinor;
  final int paymentTermsDays;
  final int outstandingMinor;
  final int availableCreditMinor;
  final bool isActive;

  bool canCoverCredit(int amountMinor) => isActive && amountMinor >= 0 && amountMinor <= availableCreditMinor;

  @override
  List<Object?> get props => [
        id,
        code,
        name,
        phone,
        email,
        creditLimitMinor,
        paymentTermsDays,
        outstandingMinor,
        availableCreditMinor,
        isActive,
      ];
}

class CustomerInvoice extends Equatable {
  const CustomerInvoice({
    required this.id,
    required this.saleNumber,
    required this.branchId,
    required this.totalMinor,
    required this.balanceDueMinor,
    required this.paymentStatus,
    required this.completedAt,
    this.dueAt,
  });

  factory CustomerInvoice.fromJson(Map<String, dynamic> json) => CustomerInvoice(
        id: json['id'].toString(),
        saleNumber: json['sale_number'].toString(),
        branchId: json['branch_id'].toString(),
        totalMinor: ScaledDecimal.toMinor(json['total'] ?? 0),
        balanceDueMinor: ScaledDecimal.toMinor(json['balance_due'] ?? 0),
        paymentStatus: json['payment_status']?.toString() ?? 'unpaid',
        completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? '') ?? DateTime.now(),
        dueAt: DateTime.tryParse(json['due_at']?.toString() ?? ''),
      );

  final String id;
  final String saleNumber;
  final String branchId;
  final int totalMinor;
  final int balanceDueMinor;
  final String paymentStatus;
  final DateTime completedAt;
  final DateTime? dueAt;

  @override
  List<Object?> get props => [
        id,
        saleNumber,
        branchId,
        totalMinor,
        balanceDueMinor,
        paymentStatus,
        completedAt,
        dueAt,
      ];
}

class CustomerDetail extends Equatable {
  const CustomerDetail({
    required this.summary,
    required this.unallocatedAdvanceMinor,
    required this.ageingMinor,
    required this.openInvoices,
    this.address,
    this.notes,
    this.isCachedOnly = false,
  });

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    final ageingJson = (json['ageing'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return CustomerDetail(
      summary: CustomerSummary.fromJson(json),
      address: json['address']?.toString(),
      notes: json['notes']?.toString(),
      unallocatedAdvanceMinor: ScaledDecimal.toMinor(json['unallocated_advance'] ?? 0),
      ageingMinor: {
        'current': ScaledDecimal.toMinor(ageingJson['current'] ?? 0),
        '1_30': ScaledDecimal.toMinor(ageingJson['1_30'] ?? 0),
        '31_60': ScaledDecimal.toMinor(ageingJson['31_60'] ?? 0),
        '61_90': ScaledDecimal.toMinor(ageingJson['61_90'] ?? 0),
        'over_90': ScaledDecimal.toMinor(ageingJson['over_90'] ?? 0),
      },
      openInvoices: ((json['open_invoices'] as List?) ?? const <dynamic>[])
          .map((value) => CustomerInvoice.fromJson((value as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  final CustomerSummary summary;
  final String? address;
  final String? notes;
  final int unallocatedAdvanceMinor;
  final Map<String, int> ageingMinor;
  final List<CustomerInvoice> openInvoices;
  final bool isCachedOnly;

  @override
  List<Object?> get props => [
        summary,
        address,
        notes,
        unallocatedAdvanceMinor,
        ageingMinor,
        openInvoices,
        isCachedOnly,
      ];
}

class CustomerStatementPayment extends Equatable {
  const CustomerStatementPayment({
    required this.id,
    required this.branchId,
    required this.amountMinor,
    required this.allocatedMinor,
    required this.advanceMinor,
    required this.method,
    required this.receivedAt,
    this.reference,
  });

  factory CustomerStatementPayment.fromJson(Map<String, dynamic> json) => CustomerStatementPayment(
        id: json['id'].toString(),
        branchId: json['branch_id'].toString(),
        amountMinor: ScaledDecimal.toMinor(json['amount'] ?? 0),
        allocatedMinor: ScaledDecimal.toMinor(json['allocated_amount'] ?? 0),
        advanceMinor: ScaledDecimal.toMinor(json['advance_amount'] ?? 0),
        method: json['method']?.toString() ?? 'unknown',
        reference: json['reference']?.toString(),
        receivedAt: DateTime.tryParse(json['received_at']?.toString() ?? '') ?? DateTime.now(),
      );

  final String id;
  final String branchId;
  final int amountMinor;
  final int allocatedMinor;
  final int advanceMinor;
  final String method;
  final String? reference;
  final DateTime receivedAt;

  @override
  List<Object?> get props => [
        id,
        branchId,
        amountMinor,
        allocatedMinor,
        advanceMinor,
        method,
        reference,
        receivedAt,
      ];
}

class CustomerStatement extends Equatable {
  const CustomerStatement({
    required this.customer,
    required this.sales,
    required this.payments,
    required this.outstandingMinor,
    required this.unallocatedAdvanceMinor,
    required this.netPositionMinor,
  });

  factory CustomerStatement.fromJson(Map<String, dynamic> json) {
    final customerJson = (json['customer'] as Map).cast<String, dynamic>();
    final summary = CustomerSummary(
      id: customerJson['id'].toString(),
      code: customerJson['code'].toString(),
      name: customerJson['name'].toString(),
      phone: customerJson['phone']?.toString(),
      email: customerJson['email']?.toString(),
      creditLimitMinor: 0,
      paymentTermsDays: 0,
      outstandingMinor: ScaledDecimal.toMinor(json['outstanding_balance'] ?? 0),
      availableCreditMinor: 0,
      isActive: true,
    );
    return CustomerStatement(
      customer: summary,
      sales: ((json['sales'] as List?) ?? const <dynamic>[])
          .map((value) => CustomerInvoice.fromJson((value as Map).cast<String, dynamic>()))
          .toList(growable: false),
      payments: ((json['payments'] as List?) ?? const <dynamic>[])
          .map((value) => CustomerStatementPayment.fromJson((value as Map).cast<String, dynamic>()))
          .toList(growable: false),
      outstandingMinor: ScaledDecimal.toMinor(json['outstanding_balance'] ?? 0),
      unallocatedAdvanceMinor: ScaledDecimal.toMinor(json['unallocated_advance'] ?? 0),
      netPositionMinor: ScaledDecimal.toMinor(json['net_position'] ?? 0),
    );
  }

  final CustomerSummary customer;
  final List<CustomerInvoice> sales;
  final List<CustomerStatementPayment> payments;
  final int outstandingMinor;
  final int unallocatedAdvanceMinor;
  final int netPositionMinor;

  @override
  List<Object?> get props => [
        customer,
        sales,
        payments,
        outstandingMinor,
        unallocatedAdvanceMinor,
        netPositionMinor,
      ];
}
