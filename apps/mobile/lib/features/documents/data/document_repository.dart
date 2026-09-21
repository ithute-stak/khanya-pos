import 'package:dio/dio.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/documents/domain/business_document.dart';

class DocumentRepository {
  DocumentRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<BusinessDocumentSummary>> listDocuments() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/documents');
    return (response.data ?? const <dynamic>[])
        .map((value) => BusinessDocumentSummary.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<BusinessDocumentSummary> uploadPurchaseReceipt({
    required String path,
    required String filename,
  }) => _upload('/documents/purchase-receipts', path: path, filename: filename);

  Future<BusinessDocumentSummary> uploadExpenseReceipt({
    required String path,
    required String filename,
  }) => _upload('/documents/expense-receipts', path: path, filename: filename);

  Future<BusinessDocumentSummary> _upload(
    String endpoint, {
    required String path,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      endpoint,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return BusinessDocumentSummary.fromJson(response.data!);
  }
}
