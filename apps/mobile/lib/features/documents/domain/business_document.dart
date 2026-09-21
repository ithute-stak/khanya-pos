import 'package:equatable/equatable.dart';

class BusinessDocumentSummary extends Equatable {
  const BusinessDocumentSummary({
    required this.id,
    required this.documentType,
    required this.originalFilename,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    required this.processingStatus,
    required this.createdAt,
    this.extractedData,
    this.duplicate = false,
  });

  factory BusinessDocumentSummary.fromJson(Map<String, dynamic> json) {
    return BusinessDocumentSummary(
      id: json['id'].toString(),
      documentType: json['document_type'].toString(),
      originalFilename: json['original_filename'].toString(),
      contentType: json['content_type'].toString(),
      byteSize: (json['byte_size'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'].toString(),
      processingStatus: json['processing_status'].toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      extractedData: json['extracted_data'] is Map<String, dynamic>
          ? json['extracted_data'] as Map<String, dynamic>
          : null,
      duplicate: json['duplicate'] as bool? ?? false,
    );
  }

  final String id;
  final String documentType;
  final String originalFilename;
  final String contentType;
  final int byteSize;
  final String sha256;
  final String processingStatus;
  final DateTime createdAt;
  final Map<String, dynamic>? extractedData;
  final bool duplicate;

  @override
  List<Object?> get props => [
        id,
        documentType,
        originalFilename,
        contentType,
        byteSize,
        sha256,
        processingStatus,
        createdAt,
        extractedData,
        duplicate,
      ];
}
