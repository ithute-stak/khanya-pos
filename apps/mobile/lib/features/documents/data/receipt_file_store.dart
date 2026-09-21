import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StoredReceiptFile {
  const StoredReceiptFile({
    required this.path,
    required this.filename,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
  });

  final String path;
  final String filename;
  final String contentType;
  final int byteSize;
  final String sha256;
}

class ReceiptFileStore {
  ReceiptFileStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  Future<StoredReceiptFile> persist({
    required String sourcePath,
    required String filename,
    required String tenantId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Receipt file is no longer available on this device.');
    }

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/khanya_receipts/$tenantId');
    await directory.create(recursive: true);

    final extension = _extension(filename);
    final storedName = '${_uuid.v4()}$extension';
    final target = await source.copy('${directory.path}/$storedName');
    final digest = await sha256.bind(target.openRead()).first;
    final byteSize = await target.length();

    return StoredReceiptFile(
      path: target.path,
      filename: filename,
      contentType: _contentType(extension),
      byteSize: byteSize,
      sha256: digest.toString(),
    );
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _extension(String filename) {
    final index = filename.lastIndexOf('.');
    if (index < 0) return '';
    final extension = filename.substring(index).toLowerCase();
    if (const {'.jpg', '.jpeg', '.png', '.webp', '.pdf'}.contains(extension)) {
      return extension;
    }
    return '';
  }

  String _contentType(String extension) {
    return switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }
}
