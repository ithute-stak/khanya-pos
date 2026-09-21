import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';
import 'package:uuid/uuid.dart';

enum CustomerPaymentSubmissionStatus { synced, queued, conflict }

class CustomerPaymentSubmission {
  const CustomerPaymentSubmission({
    required this.clientOperationId,
    required this.status,
  });

  final String clientOperationId;
  final CustomerPaymentSubmissionStatus status;
}

class CustomerRepository {
  CustomerRepository({
    required ApiClient apiClient,
    required AppDatabase appDatabase,
    required CustomerDatabase customerDatabase,
    required SessionContext sessionContext,
    required SyncService syncService,
    Uuid? uuid,
  })  : _apiClient = apiClient,
        _appDatabase = appDatabase,
        _customerDatabase = customerDatabase,
        _sessionContext = sessionContext,
        _syncService = syncService,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final AppDatabase _appDatabase;
  final CustomerDatabase _customerDatabase;
  final SessionContext _sessionContext;
  final SyncService _syncService;
  final Uuid _uuid;

  Stream<List<CustomerSummary>> watchCurrentCustomers() {
    final tenantId = _requireTenant();
    return _customerDatabase.watchCustomers(tenantId).map(
          (rows) => rows.map(_summaryFromCached).toList(growable: false),
        );
  }

  Future<List<CustomerSummary>> cachedCustomers() async {
    final tenantId = _requireTenant();
    await _reconcileCreditReservations(tenantId);
    final rows = await _customerDatabase.getCustomers(tenantId);
    return rows.map(_summaryFromCached).toList(growable: false);
  }

  Future<void> refresh() async {
    final tenantId = _requireTenant();
    await _reconcileCreditReservations(tenantId);
    final response = await _apiClient.dio.get<List<dynamic>>('/customers');
    final customers = (response.data ?? const <dynamic>[])
        .map((value) => CustomerSummary.fromJson((value as Map).cast<String, dynamic>()))
        .toList(growable: false);
    final now = DateTime.now().toUtc();
    await _customerDatabase.replaceCustomers(
      tenantId: tenantId,
      customers: [
        for (final customer in customers)
          CachedCustomersCompanion.insert(
            customerId: customer.id,
            tenantId: tenantId,
            code: customer.code,
            name: customer.name,
            phone: Value(customer.phone),
            email: Value(customer.email),
            creditLimitMinor: Value(customer.creditLimitMinor),
            paymentTermsDays: Value(customer.paymentTermsDays),
            outstandingMinor: Value(customer.outstandingMinor),
            availableCreditMinor: Value(customer.availableCreditMinor),
            isActive: Value(customer.isActive),
            updatedAt: now,
          ),
      ],
    );
  }

  Future<CustomerSummary?> cachedCustomer(String customerId) async {
    final tenantId = _requireTenant();
    final row = await _customerDatabase.getCustomer(
      tenantId: tenantId,
      customerId: customerId,
    );
    return row == null ? null : _summaryFromCached(row);
  }

  Future<CustomerDetail> getCustomer(String customerId) async {
    final tenantId = _requireTenant();
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>('/customers/$customerId');
      final detail = CustomerDetail.fromJson(response.data!);
      final now = DateTime.now().toUtc();
      await _customerDatabase.replaceCustomers(
        tenantId: tenantId,
        customers: [
          for (final row in await _customerDatabase.getCustomers(tenantId))
            if (row.customerId != customerId)
              CachedCustomersCompanion.insert(
                customerId: row.customerId,
                tenantId: row.tenantId,
                code: row.code,
                name: row.name,
                phone: Value(row.phone),
                email: Value(row.email),
                creditLimitMinor: Value(row.creditLimitMinor),
                paymentTermsDays: Value(row.paymentTermsDays),
                outstandingMinor: Value(row.outstandingMinor),
                availableCreditMinor: Value(row.availableCreditMinor),
                isActive: Value(row.isActive),
                updatedAt: row.updatedAt,
              ),
          CachedCustomersCompanion.insert(
            customerId: detail.summary.id,
            tenantId: tenantId,
            code: detail.summary.code,
            name: detail.summary.name,
            phone: Value(detail.summary.phone),
            email: Value(detail.summary.email),
            creditLimitMinor: Value(detail.summary.creditLimitMinor),
            paymentTermsDays: Value(detail.summary.paymentTermsDays),
            outstandingMinor: Value(detail.summary.outstandingMinor),
            availableCreditMinor: Value(detail.summary.availableCreditMinor),
            isActive: Value(detail.summary.isActive),
            updatedAt: now,
          ),
        ],
      );
      return detail;
    } catch (_) {
      final row = await _customerDatabase.getCustomer(
        tenantId: tenantId,
        customerId: customerId,
      );
      if (row == null) rethrow;
      return CustomerDetail(
        summary: _summaryFromCached(row),
        unallocatedAdvanceMinor: 0,
        ageingMinor: const {
          'current': 0,
          '1_30': 0,
          '31_60': 0,
          '61_90': 0,
          'over_90': 0,
        },
        openInvoices: const [],
        isCachedOnly: true,
      );
    }
  }

  Future<CustomerDetail> createCustomer({
    required String code,
    required String name,
    String? phone,
    String? email,
    String? address,
    int creditLimitMinor = 0,
    int paymentTermsDays = 0,
    String? notes,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/customers',
      data: {
        'code': code.trim(),
        'name': name.trim(),
        'phone': _blankToNull(phone),
        'email': _blankToNull(email),
        'address': _blankToNull(address),
        'credit_limit': ScaledDecimal.fromMinor(creditLimitMinor),
        'payment_terms_days': paymentTermsDays,
        'notes': _blankToNull(notes),
      },
    );
    final id = response.data!['id'].toString();
    await refresh();
    return getCustomer(id);
  }

  Future<CustomerDetail> updateCreditTerms({
    required String customerId,
    required int creditLimitMinor,
    required int paymentTermsDays,
  }) async {
    await _apiClient.dio.patch<Map<String, dynamic>>(
      '/customers/$customerId',
      data: {
        'credit_limit': ScaledDecimal.fromMinor(creditLimitMinor),
        'payment_terms_days': paymentTermsDays,
      },
    );
    await refresh();
    return getCustomer(customerId);
  }

  Future<CustomerPaymentSubmission> recordPayment({
    required String customerId,
    required int amountMinor,
    required String method,
    String? reference,
    Map<String, int> allocations = const {},
  }) async {
    if (amountMinor <= 0) throw StateError('Payment amount must be greater than zero.');
    final tenantId = _requireTenant();
    final branchId = _requireBranch();
    final clientOperationId = _uuid.v4();
    final payload = <String, dynamic>{
      'client_operation_id': clientOperationId,
      'amount': ScaledDecimal.fromMinor(amountMinor),
      'method': method,
      'reference': _blankToNull(reference),
      'allocations': [
        for (final entry in allocations.entries)
          {
            'sale_id': entry.key,
            'amount': ScaledDecimal.fromMinor(entry.value),
          },
      ],
    };
    final now = DateTime.now().toUtc();
    await _customerDatabase.queuePayment(
      payment: PendingCustomerPaymentsCompanion.insert(
        clientOperationId: clientOperationId,
        tenantId: tenantId,
        branchId: branchId,
        customerId: customerId,
        payloadJson: jsonEncode(payload),
        amountMinor: amountMinor,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _syncService.flushPendingCustomerPayments();
    final pending = await _customerDatabase.getPendingPayment(clientOperationId);
    if (pending == null) {
      try {
        await refresh();
      } catch (_) {
        // The local projection remains correct until the next successful refresh.
      }
      return CustomerPaymentSubmission(
        clientOperationId: clientOperationId,
        status: CustomerPaymentSubmissionStatus.synced,
      );
    }
    return CustomerPaymentSubmission(
      clientOperationId: clientOperationId,
      status: pending.status == 'conflict'
          ? CustomerPaymentSubmissionStatus.conflict
          : CustomerPaymentSubmissionStatus.queued,
    );
  }

  Future<CustomerStatement> getStatement(String customerId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/customers/$customerId/statement',
    );
    return CustomerStatement.fromJson(response.data!);
  }

  Future<void> _reconcileCreditReservations(String tenantId) async {
    final pendingSales = await _appDatabase.getSyncablePendingSales();
    await _customerDatabase.reconcileCreditReservations(
      tenantId: tenantId,
      activeSaleOperationIds: pendingSales
          .where((sale) => sale.tenantId == tenantId)
          .map((sale) => sale.clientOperationId)
          .toSet(),
    );
  }

  CustomerSummary _summaryFromCached(CachedCustomer row) => CustomerSummary(
        id: row.customerId,
        code: row.code,
        name: row.name,
        phone: row.phone,
        email: row.email,
        creditLimitMinor: row.creditLimitMinor,
        paymentTermsDays: row.paymentTermsDays,
        outstandingMinor: row.outstandingMinor,
        availableCreditMinor: row.availableCreditMinor,
        isActive: row.isActive,
      );

  String _requireTenant() {
    final tenantId = _sessionContext.tenantId;
    if (tenantId == null) throw StateError('A business must be selected.');
    return tenantId;
  }

  String _requireBranch() {
    final branchId = _sessionContext.branchId;
    if (branchId == null) throw StateError('A branch must be selected.');
    return branchId;
  }

  String? _blankToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
