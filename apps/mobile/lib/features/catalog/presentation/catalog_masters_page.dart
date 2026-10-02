import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';

enum CatalogMasterType { category, brand, unit }

extension on CatalogMasterType {
  String get label => switch (this) {
        CatalogMasterType.category => 'Category',
        CatalogMasterType.brand => 'Brand',
        CatalogMasterType.unit => 'Unit',
      };

  String get plural => switch (this) {
        CatalogMasterType.category => 'Categories',
        CatalogMasterType.brand => 'Brands',
        CatalogMasterType.unit => 'Units',
      };

  IconData get icon => switch (this) {
        CatalogMasterType.category => Icons.category_outlined,
        CatalogMasterType.brand => Icons.sell_outlined,
        CatalogMasterType.unit => Icons.straighten_outlined,
      };
}

class CatalogMastersPage extends StatefulWidget {
  const CatalogMastersPage({super.key});

  @override
  State<CatalogMastersPage> createState() => _CatalogMastersPageState();
}

class _CatalogMastersPageState extends State<CatalogMastersPage> {
  CatalogMasterType _type = CatalogMasterType.category;
  bool _loading = true;
  String? _error;
  List<CatalogMasterItem> _categories = const [];
  List<CatalogMasterItem> _brands = const [];
  List<CatalogMasterItem> _units = const [];

  ProductRepository get _repository => context.read<ProductRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.categories(),
        _repository.brands(),
        _repository.units(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0];
        _brands = results[1];
        _units = results[2];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Catalog lists could not be loaded. Check the connection and try again.';
      });
    }
  }

  List<CatalogMasterItem> get _items => switch (_type) {
        CatalogMasterType.category => _categories,
        CatalogMasterType.brand => _brands,
        CatalogMasterType.unit => _units,
      };

  Future<void> _add() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCatalogMasterPage(type: _type),
      ),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog setup'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _add,
        icon: const Icon(Icons.add),
        label: Text('Add ${_type.label.toLowerCase()}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reusable product data',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Keep product categories, brands and units consistent across the business.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<CatalogMasterType>(
                      segments: [
                        for (final type in CatalogMasterType.values)
                          ButtonSegment(
                            value: type,
                            icon: Icon(type.icon),
                            label: Text(type.plural),
                          ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (selection) {
                        setState(() => _type = selection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off_outlined, size: 48),
                                const SizedBox(height: 12),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _items.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_type.icon, size: 52),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No ${_type.plural.toLowerCase()} yet',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Add the first ${_type.label.toLowerCase()} for this business.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      leading: CircleAvatar(child: Icon(_type.icon)),
                                      title: Text(item.name),
                                      subtitle: Text(_type.label),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddCatalogMasterPage extends StatefulWidget {
  const AddCatalogMasterPage({super.key, required this.type});

  final CatalogMasterType type;

  @override
  State<AddCatalogMasterPage> createState() => _AddCatalogMasterPageState();
}

class _AddCatalogMasterPageState extends State<AddCatalogMasterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = context.read<ProductRepository>();
      switch (widget.type) {
        case CatalogMasterType.category:
          await repository.createCategory(_name.text);
          break;
        case CatalogMasterType.brand:
          await repository.createBrand(_name.text);
          break;
        case CatalogMasterType.unit:
          await repository.createUnit(_name.text);
          break;
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${widget.type.label} could not be created. It may already exist.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Add ${widget.type.label.toLowerCase()}')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760 ? 28.0 : 16.0;
            return Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 100),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(widget.type.icon, size: 44),
                          const SizedBox(height: 14),
                          Text(
                            'New ${widget.type.label.toLowerCase()}',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'This value will be reusable when creating and editing products.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _name,
                            autofocus: true,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                            decoration: InputDecoration(
                              labelText: '${widget.type.label} name',
                              prefixIcon: Icon(widget.type.icon),
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              final minimum = widget.type == CatalogMasterType.unit ? 1 : 2;
                              if (text.length < minimum) {
                                return 'Enter a valid ${widget.type.label.toLowerCase()} name.';
                              }
                              return null;
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Card(
                              color: theme.colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving…' : 'Save ${widget.type.label.toLowerCase()}'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
