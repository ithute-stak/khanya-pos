import 'package:khanya_pos/core/config/app_config.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/realtime/realtime_client.dart';
import 'package:khanya_pos/core/security/session_store.dart';
import 'package:khanya_pos/core/security/token_store.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/auth/data/auth_repository.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/documents/data/document_repository.dart';
import 'package:khanya_pos/features/documents/data/receipt_file_store.dart';
import 'package:khanya_pos/features/expenses/data/expense_repository.dart';
import 'package:khanya_pos/features/inventory/data/inventory_control_repository.dart';
import 'package:khanya_pos/features/pos/data/held_sales_repository.dart';
import 'package:khanya_pos/features/pos/data/sales_repository.dart';
import 'package:khanya_pos/features/pos/data/till_repository.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/reports/data/reports_repository.dart';
import 'package:khanya_pos/features/staff/data/staff_repository.dart';

class AppDependencies {
  AppDependencies._({
    required this.database,
    required this.customerDatabase,
    required this.sessionContext,
    required this.apiClient,
    required this.authRepository,
    required this.productRepository,
    required this.customerRepository,
    required this.inventoryControlRepository,
    required this.syncService,
    required this.salesRepository,
    required this.heldSalesRepository,
    required this.tillRepository,
    required this.purchasingRepository,
    required this.documentRepository,
    required this.expenseRepository,
    required this.reportsRepository,
    required this.staffRepository,
    required this.accountingRepository,
    required this.hardwareSettingsRepository,
    required this.realtimeClient,
  });

  factory AppDependencies.create() {
    final database = AppDatabase();
    final customerDatabase = CustomerDatabase();
    final sessionContext = SessionContext();
    final apiClient = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      requestHeadersProvider: sessionContext.requestHeaders,
    );
    final authRepository = AuthRepository(
      apiClient: apiClient,
      tokenStore: TokenStore(),
      sessionStore: SessionStore(),
      sessionContext: sessionContext,
    );
    sessionContext.setRefreshCallback(authRepository.refreshAccessToken);
    apiClient.setUnauthorizedHandler(sessionContext.refreshAccessToken);
    final productRepository = ProductRepository(
      apiClient: apiClient,
      database: database,
      sessionContext: sessionContext,
    );
    final inventoryControlRepository = InventoryControlRepository(
      apiClient: apiClient,
      sessionContext: sessionContext,
    );
    final syncService = SyncService(
      apiClient: apiClient,
      database: database,
      customerDatabase: customerDatabase,
    );
    final customerRepository = CustomerRepository(
      apiClient: apiClient,
      appDatabase: database,
      customerDatabase: customerDatabase,
      sessionContext: sessionContext,
      syncService: syncService,
    );
    final salesRepository = SalesRepository(
      apiClient: apiClient,
      database: database,
      customerDatabase: customerDatabase,
      sessionContext: sessionContext,
      syncService: syncService,
    );
    final heldSalesRepository = HeldSalesRepository(sessionContext: sessionContext);
    final tillRepository = TillRepository(
      apiClient: apiClient,
      database: database,
      sessionContext: sessionContext,
    );
    final purchasingRepository = PurchasingRepository(
      apiClient: apiClient,
      database: database,
      sessionContext: sessionContext,
      syncService: syncService,
    );
    final documentRepository = DocumentRepository(
      database: database,
      sessionContext: sessionContext,
      syncService: syncService,
      fileStore: ReceiptFileStore(),
      remoteList: () async =>
          (await apiClient.dio.get<List<dynamic>>('/documents')).data ?? const <dynamic>[],
    );
    final expenseRepository = ExpenseRepository(
      apiClient: apiClient,
      database: database,
      sessionContext: sessionContext,
      syncService: syncService,
    );
    final reportsRepository = ReportsRepository(apiClient: apiClient);
    final staffRepository = StaffRepository(apiClient: apiClient);
    final accountingRepository = AccountingRepository(apiClient: apiClient);
    return AppDependencies._(
      database: database,
      customerDatabase: customerDatabase,
      sessionContext: sessionContext,
      apiClient: apiClient,
      authRepository: authRepository,
      productRepository: productRepository,
      customerRepository: customerRepository,
      inventoryControlRepository: inventoryControlRepository,
      syncService: syncService,
      salesRepository: salesRepository,
      heldSalesRepository: heldSalesRepository,
      tillRepository: tillRepository,
      purchasingRepository: purchasingRepository,
      documentRepository: documentRepository,
      expenseRepository: expenseRepository,
      reportsRepository: reportsRepository,
      staffRepository: staffRepository,
      accountingRepository: accountingRepository,
      hardwareSettingsRepository: PosHardwareSettingsRepository(),
      realtimeClient: RealtimeClient(),
    );
  }

  final AppDatabase database;
  final CustomerDatabase customerDatabase;
  final SessionContext sessionContext;
  final ApiClient apiClient;
  final AuthRepository authRepository;
  final ProductRepository productRepository;
  final CustomerRepository customerRepository;
  final InventoryControlRepository inventoryControlRepository;
  final SyncService syncService;
  final SalesRepository salesRepository;
  final HeldSalesRepository heldSalesRepository;
  final TillRepository tillRepository;
  final PurchasingRepository purchasingRepository;
  final DocumentRepository documentRepository;
  final ExpenseRepository expenseRepository;
  final ReportsRepository reportsRepository;
  final StaffRepository staffRepository;
  final AccountingRepository accountingRepository;
  final PosHardwareSettingsRepository hardwareSettingsRepository;
  final RealtimeClient realtimeClient;

  Future<void> close() async {
    await realtimeClient.close();
    await sessionContext.close();
    await customerDatabase.close();
    await database.close();
    apiClient.dio.close(force: true);
  }
}
