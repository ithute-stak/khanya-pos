import 'dart:convert';

/// Display-only QR locator inspection.
///
/// The authoritative signature, expiry, tenant, branch and record permissions
/// MUST be verified on the backend before a resource may be opened by ID.
/// This parser only chooses a safe module landing page, never a mutation.
class QrScanTarget {
  const QrScanTarget({
    required this.kind,
    required this.modulePath,
    required this.moduleLabel,
  });

  final String kind;
  final String modulePath;
  final String moduleLabel;
}

const Map<String, String> qrModulePaths = {
  'product': '/products',
  'sale': '/sales',
  'receipt': '/sales',
  'customer': '/customers',
  'loyalty': '/customers',
  'inventory_item': '/inventory',
  'stocktake': '/inventory/controls',
  'stock_location': '/inventory',
  'purchase_order': '/purchase-orders',
  'supplier': '/suppliers',
  'appointment': '/appointments',
  'staff': '/staff',
  'device': '/devices',
  'payment_request': '/pos',
};

const Map<String, String> qrModuleLabels = {
  'product': 'Products',
  'sale': 'Sales history',
  'receipt': 'Sales receipts',
  'customer': 'Customers',
  'loyalty': 'Customer loyalty',
  'inventory_item': 'Inventory',
  'stocktake': 'Stocktakes',
  'stock_location': 'Inventory locations',
  'purchase_order': 'Purchase orders',
  'supplier': 'Suppliers',
  'appointment': 'Appointments',
  'staff': 'Staff',
  'device': 'Devices',
  'payment_request': 'POS checkout',
};

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

QrScanTarget? inspectKhanyaQrLocator(String value) {
  // Deliberately do not infer permissions or an authoritative payment state.
  const prefix = 'khanyaqr:v1:';
  if (!value.startsWith(prefix) || value.length > 1200) return null;
  final parts = value.substring(prefix.length).split('.');
  if (parts.length != 2 || parts.any((part) => part.isEmpty)) return null;
  try {
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(parts.first)));
    final payload = jsonDecode(decoded);
    if (payload is! Map<String, dynamic>) return null;
    if (payload['v'] != 1) return null;
    if (payload.keys.toSet().difference({'v', 'k', 'r', 't', 'b', 'e'}).isNotEmpty ||
        payload.length != 6) return null;
    final kind = payload['k'];
    if (kind is! String || !qrModulePaths.containsKey(kind)) return null;
    if (payload['r'] is! String || !_uuid.hasMatch(payload['r'] as String)) return null;
    if (payload['t'] is! String || !_uuid.hasMatch(payload['t'] as String)) return null;
    if (payload['b'] != null &&
        (payload['b'] is! String || !_uuid.hasMatch(payload['b'] as String))) {
      return null;
    }
    if (payload['e'] is! int) return null;
    if (parts.last.length != 43 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts.last)) {
      return null;
    }
    return QrScanTarget(
      kind: kind,
      modulePath: qrModulePaths[kind]!,
      moduleLabel: qrModuleLabels[kind]!,
    );
  } catch (_) {
    return null;
  }
}
