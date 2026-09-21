import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/documents/domain/business_document.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';

sealed class PurchaseDraftEvent extends Equatable {
  const PurchaseDraftEvent();
  @override
  List<Object?> get props => [];
}

final class PurchaseDraftStarted extends PurchaseDraftEvent {
  const PurchaseDraftStarted();
}

final class PurchaseDraftSupplierSelected extends PurchaseDraftEvent {
  const PurchaseDraftSupplierSelected(this.supplierId);
  final String? supplierId;
  @override
  List<Object?> get props => [supplierId];
}

final class PurchaseDraftProductAdded extends PurchaseDraftEvent {
  const PurchaseDraftProductAdded(this.product);
  final ProductSummary product;
  @override
  List<Object?> get props => [product];
}

final class PurchaseDraftLineRemoved extends PurchaseDraftEvent {
  const PurchaseDraftLineRemoved(this.productId);
  final String productId;
  @override
  List<Object?> get props => [productId];
}

final class PurchaseDraftQuantityChanged extends PurchaseDraftEvent {
  const PurchaseDraftQuantityChanged({required this.productId, required this.value});
  final String productId;
  final String value;
  @override
  List<Object?> get props => [productId, value];
}

final class PurchaseDraftCostChanged extends PurchaseDraftEvent {
  const PurchaseDraftCostChanged({required this.productId, required this.value});
  final String productId;
  final String value;
  @override
  List<Object?> get props => [productId, value];
}

final class PurchaseDraftReceiptAttached extends PurchaseDraftEvent {
  const PurchaseDraftReceiptAttached(this.document);
  final BusinessDocumentSummary document;
  @override
  List<Object?> get props => [document];
}

final class PurchaseDraftPaymentMethodChanged extends PurchaseDraftEvent {
  const PurchaseDraftPaymentMethodChanged(this.method);
  final String method;
  @override
  List<Object?> get props => [method];
}

final class PurchaseDraftAmountPaidChanged extends PurchaseDraftEvent {
  const PurchaseDraftAmountPaidChanged(this.value);
  final String value;
  @override
  List<Object?> get props => [value];
}

final class PurchaseDraftInvoiceChanged extends PurchaseDraftEvent {
  const PurchaseDraftInvoiceChanged(this.value);
  final String value;
  @override
  List<Object?> get props => [value];
}

final class PurchaseDraftNotesChanged extends PurchaseDraftEvent {
  const PurchaseDraftNotesChanged(this.value);
  final String value;
  @override
  List<Object?> get props => [value];
}

final class PurchaseDraftSubmitted extends PurchaseDraftEvent {
  const PurchaseDraftSubmitted();
}

enum PurchaseDraftStatus { initial, loading, ready, submitting, success, failure }

class PurchaseDraftState extends Equatable {
  const PurchaseDraftState({
    this.status = PurchaseDraftStatus.initial,
    this.suppliers = const [],
    this.products = const [],
    this.lines = const [],
    this.supplierId,
    this.receipt,
    this.paymentMethod = 'cash',
    this.amountPaidMinor = 0,
    this.invoiceNumber = '',
    this.notes = '',
    this.message,
    this.submission,
  });

  final PurchaseDraftStatus status;
  final List<SupplierSummary> suppliers;
  final List<ProductSummary> products;
  final List<PurchaseDraftLine> lines;
  final String? supplierId;
  final BusinessDocumentSummary? receipt;
  final String paymentMethod;
  final int amountPaidMinor;
  final String invoiceNumber;
  final String notes;
  final String? message;
  final PurchaseSubmission? submission;

  int get totalMinor => lines.fold(0, (total, line) => total + line.lineTotalMinor);
  int get balanceDueMinor => totalMinor - amountPaidMinor;
  bool get canSubmit =>
      status != PurchaseDraftStatus.submitting &&
      lines.isNotEmpty &&
      lines.every((line) => line.quantityMilli > 0 && line.unitCostMinor >= 0) &&
      amountPaidMinor >= 0 &&
      amountPaidMinor <= totalMinor;

  PurchaseDraftState copyWith({
    PurchaseDraftStatus? status,
    List<SupplierSummary>? suppliers,
    List<ProductSummary>? products,
    List<PurchaseDraftLine>? lines,
    String? supplierId,
    bool clearSupplier = false,
    BusinessDocumentSummary? receipt,
    String? paymentMethod,
    int? amountPaidMinor,
    String? invoiceNumber,
    String? notes,
    String? message,
    bool clearMessage = false,
    PurchaseSubmission? submission,
  }) {
    return PurchaseDraftState(
      status: status ?? this.status,
      suppliers: suppliers ?? this.suppliers,
      products: products ?? this.products,
      lines: lines ?? this.lines,
      supplierId: clearSupplier ? null : supplierId ?? this.supplierId,
      receipt: receipt ?? this.receipt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amountPaidMinor: amountPaidMinor ?? this.amountPaidMinor,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      notes: notes ?? this.notes,
      message: clearMessage ? null : message ?? this.message,
      submission: submission ?? this.submission,
    );
  }

  @override
  List<Object?> get props => [
        status,
        suppliers,
        products,
        lines,
        supplierId,
        receipt,
        paymentMethod,
        amountPaidMinor,
        invoiceNumber,
        notes,
        message,
        submission,
      ];
}

class PurchaseDraftBloc extends Bloc<PurchaseDraftEvent, PurchaseDraftState> {
  PurchaseDraftBloc({
    required PurchasingRepository purchasingRepository,
    required ProductRepository productRepository,
  })  : _purchasingRepository = purchasingRepository,
        _productRepository = productRepository,
        super(const PurchaseDraftState()) {
    on<PurchaseDraftStarted>(_onStarted);
    on<PurchaseDraftSupplierSelected>((event, emit) {
      emit(state.copyWith(supplierId: event.supplierId, clearSupplier: event.supplierId == null));
    });
    on<PurchaseDraftProductAdded>(_onProductAdded);
    on<PurchaseDraftLineRemoved>((event, emit) {
      emit(state.copyWith(lines: state.lines.where((line) => line.product.id != event.productId).toList()));
    });
    on<PurchaseDraftQuantityChanged>(_onQuantityChanged);
    on<PurchaseDraftCostChanged>(_onCostChanged);
    on<PurchaseDraftReceiptAttached>((event, emit) => emit(state.copyWith(receipt: event.document)));
    on<PurchaseDraftPaymentMethodChanged>((event, emit) {
      emit(
        state.copyWith(
          paymentMethod: event.method,
          amountPaidMinor: event.method == 'supplier_credit' ? 0 : state.amountPaidMinor,
        ),
      );
    });
    on<PurchaseDraftAmountPaidChanged>((event, emit) {
      emit(state.copyWith(amountPaidMinor: ScaledDecimal.toMinor(event.value)));
    });
    on<PurchaseDraftInvoiceChanged>((event, emit) => emit(state.copyWith(invoiceNumber: event.value)));
    on<PurchaseDraftNotesChanged>((event, emit) => emit(state.copyWith(notes: event.value)));
    on<PurchaseDraftSubmitted>(_onSubmitted);
  }

  final PurchasingRepository _purchasingRepository;
  final ProductRepository _productRepository;

  Future<void> _onStarted(PurchaseDraftStarted event, Emitter<PurchaseDraftState> emit) async {
    emit(state.copyWith(status: PurchaseDraftStatus.loading, clearMessage: true));
    try {
      try {
        await _productRepository.refresh();
      } catch (_) {
        // Cached products keep purchase entry available when the catalog refresh is unavailable.
      }
      final suppliers = await _purchasingRepository.listSuppliers();
      final products = await _productRepository.cachedCurrentCatalog();
      emit(
        state.copyWith(
          status: PurchaseDraftStatus.ready,
          suppliers: suppliers,
          products: products,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: PurchaseDraftStatus.failure,
          message: 'Could not prepare a new purchase. Check connectivity and business context.',
        ),
      );
    }
  }

  void _onProductAdded(PurchaseDraftProductAdded event, Emitter<PurchaseDraftState> emit) {
    if (state.lines.any((line) => line.product.id == event.product.id)) return;
    emit(
      state.copyWith(
        lines: [
          ...state.lines,
          PurchaseDraftLine(
            product: event.product,
            quantityMilli: 1000,
            unitCostMinor: event.product.costPriceMinor,
          ),
        ],
      ),
    );
  }

  void _onQuantityChanged(PurchaseDraftQuantityChanged event, Emitter<PurchaseDraftState> emit) {
    final next = state.lines.map((line) {
      if (line.product.id != event.productId) return line;
      return line.copyWith(quantityMilli: ScaledDecimal.toMilli(event.value));
    }).toList(growable: false);
    emit(state.copyWith(lines: next));
  }

  void _onCostChanged(PurchaseDraftCostChanged event, Emitter<PurchaseDraftState> emit) {
    final next = state.lines.map((line) {
      if (line.product.id != event.productId) return line;
      return line.copyWith(unitCostMinor: ScaledDecimal.toMinor(event.value));
    }).toList(growable: false);
    emit(state.copyWith(lines: next));
  }

  Future<void> _onSubmitted(PurchaseDraftSubmitted event, Emitter<PurchaseDraftState> emit) async {
    if (!state.canSubmit) {
      emit(state.copyWith(message: 'Check purchase items and payment amount before saving.'));
      return;
    }
    emit(state.copyWith(status: PurchaseDraftStatus.submitting, clearMessage: true));
    try {
      final submission = await _purchasingRepository.receivePurchase(
        supplierId: state.supplierId,
        supplierInvoiceNumber: state.invoiceNumber,
        paymentMethod: state.paymentMethod,
        amountPaidMinor: state.amountPaidMinor,
        receiptDocumentId: state.receipt?.id,
        notes: state.notes,
        lines: state.lines,
      );
      try {
        await _productRepository.refresh();
      } catch (_) {
        // The purchase is already committed server-side; realtime/sync can reconcile later.
      }
      emit(
        state.copyWith(
          status: PurchaseDraftStatus.success,
          submission: submission,
          message: '${submission.purchaseNumber} saved successfully.',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: PurchaseDraftStatus.failure,
          message: 'Purchase could not be saved. Review the values and connectivity.',
        ),
      );
    }
  }
}
