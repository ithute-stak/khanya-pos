import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/documents/data/document_repository.dart';
import 'package:khanya_pos/features/documents/data/receipt_picker.dart';
import 'package:khanya_pos/features/documents/domain/business_document.dart';

sealed class ReceiptCaptureEvent extends Equatable {
  const ReceiptCaptureEvent();

  @override
  List<Object?> get props => [];
}

final class ReceiptVaultRequested extends ReceiptCaptureEvent {
  const ReceiptVaultRequested();
}

final class ReceiptCaptureRequested extends ReceiptCaptureEvent {
  const ReceiptCaptureRequested({required this.source, required this.purpose});
  final ReceiptSource source;
  final ReceiptPurpose purpose;

  @override
  List<Object?> get props => [source, purpose];
}

final class ReceiptSelectionCleared extends ReceiptCaptureEvent {
  const ReceiptSelectionCleared();
}

class ReceiptCaptureState extends Equatable {
  const ReceiptCaptureState({
    this.documents = const [],
    this.selected,
    this.isLoading = false,
    this.isUploading = false,
    this.message,
  });

  final List<BusinessDocumentSummary> documents;
  final BusinessDocumentSummary? selected;
  final bool isLoading;
  final bool isUploading;
  final String? message;

  ReceiptCaptureState copyWith({
    List<BusinessDocumentSummary>? documents,
    BusinessDocumentSummary? selected,
    bool clearSelected = false,
    bool? isLoading,
    bool? isUploading,
    String? message,
    bool clearMessage = false,
  }) {
    return ReceiptCaptureState(
      documents: documents ?? this.documents,
      selected: clearSelected ? null : selected ?? this.selected,
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      message: clearMessage ? null : message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [documents, selected, isLoading, isUploading, message];
}

class ReceiptCaptureBloc extends Bloc<ReceiptCaptureEvent, ReceiptCaptureState> {
  ReceiptCaptureBloc({required DocumentRepository repository, ReceiptPicker? picker})
      : _repository = repository,
        _picker = picker ?? ReceiptPicker(),
        super(const ReceiptCaptureState()) {
    on<ReceiptVaultRequested>(_onVaultRequested);
    on<ReceiptCaptureRequested>(_onCaptureRequested);
    on<ReceiptSelectionCleared>((event, emit) => emit(state.copyWith(clearSelected: true)));
  }

  final DocumentRepository _repository;
  final ReceiptPicker _picker;

  Future<void> _onVaultRequested(
    ReceiptVaultRequested event,
    Emitter<ReceiptCaptureState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearMessage: true));
    try {
      final documents = await _repository.listDocuments();
      emit(state.copyWith(documents: documents, isLoading: false));
    } catch (_) {
      emit(state.copyWith(isLoading: false, message: 'Could not load the receipt vault.'));
    }
  }

  Future<void> _onCaptureRequested(
    ReceiptCaptureRequested event,
    Emitter<ReceiptCaptureState> emit,
  ) async {
    emit(state.copyWith(isUploading: true, clearMessage: true));
    try {
      final picked = await _picker.pick(event.source);
      if (picked == null) {
        emit(state.copyWith(isUploading: false));
        return;
      }
      final document = event.purpose == ReceiptPurpose.purchase
          ? await _repository.uploadPurchaseReceipt(path: picked.path, filename: picked.name)
          : await _repository.uploadExpenseReceipt(path: picked.path, filename: picked.name);
      final documents = [
        document,
        ...state.documents.where((item) => item.id != document.id),
      ];
      emit(
        state.copyWith(
          documents: documents,
          selected: document,
          isUploading: false,
          message: document.duplicate
              ? 'This receipt was already in the vault. The existing copy was selected.'
              : 'Receipt uploaded and attached.',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isUploading: false,
          message: 'Receipt upload failed. Check connectivity and try again.',
        ),
      );
    }
  }
}
