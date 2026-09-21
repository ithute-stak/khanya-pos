import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/documents/data/receipt_picker.dart';
import 'package:khanya_pos/features/documents/presentation/bloc/receipt_capture_bloc.dart';

class ReceiptCaptureButtons extends StatelessWidget {
  const ReceiptCaptureButtons({super.key, required this.purpose});

  final ReceiptPurpose purpose;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ReceiptCaptureBloc>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: state.isUploading
                  ? null
                  : () => context.read<ReceiptCaptureBloc>().add(
                        ReceiptCaptureRequested(source: ReceiptSource.camera, purpose: purpose),
                      ),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Camera'),
            ),
            FilledButton.tonalIcon(
              onPressed: state.isUploading
                  ? null
                  : () => context.read<ReceiptCaptureBloc>().add(
                        ReceiptCaptureRequested(source: ReceiptSource.gallery, purpose: purpose),
                      ),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
            ),
            OutlinedButton.icon(
              onPressed: state.isUploading
                  ? null
                  : () => context.read<ReceiptCaptureBloc>().add(
                        ReceiptCaptureRequested(source: ReceiptSource.pdf, purpose: purpose),
                      ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
          ],
        ),
        if (state.isUploading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (state.selected != null) ...[
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
            title: Text(state.selected!.originalFilename, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${state.selected!.processingStatus.replaceAll('_', ' ')} • ${_formatBytes(state.selected!.byteSize)}',
            ),
            trailing: const Icon(Icons.check_circle, color: Colors.green),
          ),
        ],
        if (state.message != null) ...[
          const SizedBox(height: 8),
          Text(state.message!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
