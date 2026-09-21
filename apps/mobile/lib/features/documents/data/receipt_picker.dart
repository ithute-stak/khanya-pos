import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

enum ReceiptSource { camera, gallery, pdf }

enum ReceiptPurpose { purchase, expense }

class PickedReceipt {
  const PickedReceipt({required this.path, required this.name});
  final String path;
  final String name;
}

class ReceiptPicker {
  ReceiptPicker({ImagePicker? imagePicker}) : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<PickedReceipt?> pick(ReceiptSource source) async {
    switch (source) {
      case ReceiptSource.camera:
        final file = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
          maxWidth: 2200,
        );
        return file == null ? null : PickedReceipt(path: file.path, name: file.name);
      case ReceiptSource.gallery:
        final file = await _imagePicker.pickImage(source: ImageSource.gallery);
        return file == null ? null : PickedReceipt(path: file.path, name: file.name);
      case ReceiptSource.pdf:
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (file == null) return null;
        return PickedReceipt(path: file.xFile.path, name: file.name);
    }
  }
}
