import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/documents/data/receipt_file_store.dart';
import 'package:khanya_pos/features/documents/domain/business_document.dart';
import 'package:uuid/uuid.dart';

class DocumentRepository {
  DocumentRepository({
    required AppDatabase database,
    required SessionContext sessionContext,
    required SyncService syncService,
    required ReceiptFileStore fileStore,
    required Future<List<dynamic>> Function() remoteList,
    Uuid? uuid,
  })  : _database = database,
        _sessionContext = sessionContext,
        _syncService = syncService,
        _fileStore = fileStore,
        _remoteList = remoteList,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final SessionContext _sessionContext;
  final SyncService _syncService;
  final ReceiptFileStore _fileStore;
  final Future<List<dynamic>> Function() _remoteList;
  final Uuid _uuid;

  Future<List<BusinessDocumentSummary>> listDocuments() async {
    final tenantId = _requireTenant();
    final branchId = _requireBranch();
    final localRows = await _database.getPendingDocuments(
      tenantId: tenantId,
      branchId: branchId,
    );
    final local = localRows.map(_fromLocal).toList(growable: false);

    try {
      final rawRemote = await _remoteList();
      final remote = rawRemote
          .map((value) => BusinessDocumentSummary.fromJson(value as Map<String, dynamic>))
          .toList(growable: false);
      final remoteIds = remote.map((item) => item.id).toSet();
      return [
        ...local.where((item) {
          final row = localRows.firstWhere((entry) => entry.localDocumentId == item.id);
          return row.remoteDocumentId == null || !remoteIds.contains(row.remoteDocumentId);
        }),
        ...remote,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return local;
    }
  }

  Future<BusinessDocumentSummary> uploadPurchaseReceipt({
    required String path,
    required String filename,
  }) => _queue(path: path, filename: filename, purpose: 'purchase');

  Future<BusinessDocumentSummary> uploadExpenseReceipt({
    required String path,
    required String filename,
  }) => _queue(path: path, filename: filename, purpose: 'expense');

  Future<BusinessDocumentSummary> _queue({
    required String path,
    required String filename,
    required String purpose,
  }) async {
    final tenantId = _requireTenant();
    final branchId = _requireBranch();
    final stored = await _fileStore.persist(
      sourcePath: path,
      filename: filename,
      tenantId: tenantId,
    );
    final now = DateTime.now().toUtc();
    final queued = await _database.queueDocument(
      PendingDocumentsCompanion.insert(
        localDocumentId: _uuid.v4(),
        tenantId: tenantId,
        branchId: branchId,
        documentPurpose: purpose,
        localPath: stored.path,
        filename: stored.filename,
        contentType: stored.contentType,
        byteSize: stored.byteSize,
        sha256: stored.sha256,
        createdAt: now,
        updatedAt: now,
      ),
    );

    if (queued.localPath != stored.path) {
      await _fileStore.delete(stored.path);
    }

    await _syncService.flushPendingDocuments();
    return _fromLocal(await _database.getPendingDocument(queued.localDocumentId) ?? queued);
  }

  BusinessDocumentSummary _fromLocal(PendingDocument row) {
    return BusinessDocumentSummary(
      id: row.localDocumentId,
      documentType: '${row.documentPurpose}_receipt',
      originalFilename: row.filename,
      contentType: row.contentType,
      byteSize: row.byteSize,
      sha256: row.sha256,
      processingStatus: row.status,
      createdAt: row.createdAt,
    );
  }

  String _requireTenant() {
    final value = _sessionContext.tenantId;
    if (value == null) throw StateError('No business selected');
    return value;
  }

  String _requireBranch() {
    final value = _sessionContext.branchId;
    if (value == null) throw StateError('No branch selected');
    return value;
  }
}
