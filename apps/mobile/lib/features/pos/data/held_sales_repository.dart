import 'dart:convert';
import 'dart:io';

import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class HeldSaleLine {
  const HeldSaleLine({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': quantity,
      };

  factory HeldSaleLine.fromJson(Map<String, dynamic> json) => HeldSaleLine(
        productId: json['product_id']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      );
}

class HeldSale {
  const HeldSale({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.label,
    required this.createdAt,
    required this.paymentMethod,
    required this.lines,
    required this.itemCount,
    required this.totalMinor,
  });

  final String id;
  final String tenantId;
  final String branchId;
  final String label;
  final DateTime createdAt;
  final PaymentMethod paymentMethod;
  final List<HeldSaleLine> lines;
  final int itemCount;
  final int totalMinor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'branch_id': branchId,
        'label': label,
        'created_at': createdAt.toUtc().toIso8601String(),
        'payment_method': paymentMethod.apiValue,
        'item_count': itemCount,
        'total_minor': totalMinor,
        'lines': lines.map((line) => line.toJson()).toList(growable: false),
      };

  factory HeldSale.fromJson(Map<String, dynamic> json) {
    final paymentValue = json['payment_method']?.toString();
    final paymentMethod = PaymentMethod.values.firstWhere(
      (method) => method.apiValue == paymentValue,
      orElse: () => PaymentMethod.cash,
    );
    final rawLines = json['lines'];
    return HeldSale(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      branchId: json['branch_id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Held sale',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      paymentMethod: paymentMethod,
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map((line) => HeldSaleLine.fromJson(Map<String, dynamic>.from(line)))
              .where((line) => line.productId.isNotEmpty && line.quantity > 0)
              .toList(growable: false)
          : const [],
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      totalMinor: (json['total_minor'] as num?)?.toInt() ?? 0,
    );
  }
}

class HeldSalesRepository {
  HeldSalesRepository({
    required SessionContext sessionContext,
    Uuid? uuid,
  })  : _sessionContext = sessionContext,
        _uuid = uuid ?? const Uuid();

  final SessionContext _sessionContext;
  final Uuid _uuid;

  Future<List<HeldSale>> listCurrentBranch() async {
    final tenantId = _sessionContext.tenantId;
    final branchId = _sessionContext.branchId;
    if (tenantId == null || branchId == null) return const [];
    final all = await _readAll();
    final matching = all
        .where((sale) => sale.tenantId == tenantId && sale.branchId == branchId)
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(matching);
  }

  Future<HeldSale> hold({
    required List<CartLine> lines,
    required PaymentMethod paymentMethod,
    required String label,
  }) async {
    if (lines.isEmpty) throw StateError('The cart is empty');
    final tenantId = _sessionContext.tenantId;
    final branchId = _sessionContext.branchId;
    if (tenantId == null || branchId == null) {
      throw StateError('A business and branch must be selected');
    }

    final heldSale = HeldSale(
      id: _uuid.v4(),
      tenantId: tenantId,
      branchId: branchId,
      label: label.trim().isEmpty ? 'Held sale' : label.trim(),
      createdAt: DateTime.now(),
      paymentMethod: paymentMethod,
      lines: lines
          .map((line) => HeldSaleLine(productId: line.product.id, quantity: line.quantity))
          .toList(growable: false),
      itemCount: lines.fold(0, (total, line) => total + line.quantity),
      totalMinor: lines.fold(0, (total, line) => total + line.lineTotalMinor),
    );

    final all = await _readAll();
    await _writeAll([...all, heldSale]);
    return heldSale;
  }

  Future<void> remove(String id) async {
    final all = await _readAll();
    await _writeAll(all.where((sale) => sale.id != id).toList(growable: false));
  }

  Future<File> _storageFile() async {
    final directory = await getApplicationSupportDirectory();
    final folder = Directory('${directory.path}${Platform.pathSeparator}khanya_pos');
    if (!await folder.exists()) await folder.create(recursive: true);
    return File('${folder.path}${Platform.pathSeparator}held_sales.json');
  }

  Future<List<HeldSale>> _readAll() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return const [];
      final text = await file.readAsString();
      if (text.trim().isEmpty) return const [];
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => HeldSale.fromJson(Map<String, dynamic>.from(item)))
          .where((sale) => sale.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeAll(List<HeldSale> sales) async {
    final file = await _storageFile();
    final payload = jsonEncode(sales.map((sale) => sale.toJson()).toList(growable: false));
    await file.writeAsString(payload, flush: true);
  }
}
