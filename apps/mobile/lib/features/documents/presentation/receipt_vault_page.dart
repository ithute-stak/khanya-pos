import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/documents/data/document_repository.dart';
import 'package:khanya_pos/features/documents/data/receipt_picker.dart';
import 'package:khanya_pos/features/documents/presentation/bloc/receipt_capture_bloc.dart';
import 'package:khanya_pos/features/documents/presentation/receipt_capture_buttons.dart';

class ReceiptVaultPage extends StatelessWidget {
  const ReceiptVaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ReceiptCaptureBloc(repository: context.read<DocumentRepository>())
        ..add(const ReceiptVaultRequested()),
      child: const _ReceiptVaultView(),
    );
  }
}

class _ReceiptVaultView extends StatelessWidget {
  const _ReceiptVaultView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ReceiptCaptureBloc>().state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Vault'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => context.read<ReceiptCaptureBloc>().add(const ReceiptVaultRequested()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;
          return RefreshIndicator(
            onRefresh: () async {
              context.read<ReceiptCaptureBloc>().add(const ReceiptVaultRequested());
              await context.read<ReceiptCaptureBloc>().stream.firstWhere((value) => !value.isLoading);
            },
            child: ListView(
              padding: EdgeInsets.all(padding),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add supporting document', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text('Photograph a shopping receipt, choose an image, or upload a supplier PDF.'),
                        const SizedBox(height: 14),
                        const ReceiptCaptureButtons(purpose: ReceiptPurpose.purchase),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('Stored documents', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    Text('${state.documents.length}'),
                  ],
                ),
                const SizedBox(height: 8),
                if (state.isLoading)
                  const LinearProgressIndicator()
                else if (state.documents.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No receipts have been stored for this business yet.'),
                    ),
                  )
                else
                  ...state.documents.map(
                    (document) => Card(
                      child: ListTile(
                        leading: Icon(
                          document.contentType == 'application/pdf'
                              ? Icons.picture_as_pdf_outlined
                              : Icons.receipt_long_outlined,
                        ),
                        title: Text(document.originalFilename, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${document.documentType.replaceAll('_', ' ')} • ${document.processingStatus.replaceAll('_', ' ')}\n'
                          '${document.createdAt.toLocal().toString().substring(0, 16)}',
                        ),
                        isThreeLine: true,
                        trailing: document.extractedData == null
                            ? const Chip(label: Text('Awaiting review'))
                            : const Icon(Icons.verified_outlined),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
