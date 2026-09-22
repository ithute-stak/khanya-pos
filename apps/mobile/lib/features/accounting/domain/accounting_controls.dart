import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class AccountSummary extends Equatable {
  const AccountSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.accountType,
    required this.reportGroup,
    required this.normalBalance,
    required this.isSystem,
    required this.isActive,
  });

  factory AccountSummary.fromJson(Map<String, dynamic> json) => AccountSummary(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        accountType: json['account_type']?.toString() ?? '',
        reportGroup: json['report_group']?.toString() ?? '',
        normalBalance: json['normal_balance']?.toString() ?? '',
        isSystem: json['is_system'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
      );

  final String id;
  final String code;
  final String name;
  final String accountType;
  final String reportGroup;
  final String normalBalance;
  final bool isSystem;
  final bool isActive;

  @override
  List<Object?> get props => [id, code, name, accountType, reportGroup, normalBalance, isSystem, isActive];
}

class ManualJournalLineDraft extends Equatable {
  const ManualJournalLineDraft({
    required this.accountCode,
    this.debitMinor = 0,
    this.creditMinor = 0,
    this.memo,
  });

  final String accountCode;
  final int debitMinor;
  final int creditMinor;
  final String? memo;

  bool get isValid =>
      accountCode.trim().isNotEmpty &&
      ((debitMinor > 0 && creditMinor == 0) || (creditMinor > 0 && debitMinor == 0));

  Map<String, dynamic> toJson() => {
        'account_code': accountCode.trim(),
        'debit': ScaledDecimal.fromMinor(debitMinor),
        'credit': ScaledDecimal.fromMinor(creditMinor),
        if (memo != null && memo!.trim().isNotEmpty) 'memo': memo!.trim(),
      };

  @override
  List<Object?> get props => [accountCode, debitMinor, creditMinor, memo];
}

class AccountingControlsData extends Equatable {
  const AccountingControlsData({required this.accounts, required this.settings});

  final List<AccountSummary> accounts;
  final DateTime? lockedThrough;
  final String? lockReason;

  AccountingControlsData._({
    required this.accounts,
    required this.lockedThrough,
    required this.lockReason,
  });

  factory AccountingControlsData.fromSettings({
    required List<AccountSummary> accounts,
    required Map<String, dynamic> settings,
  }) => AccountingControlsData._(
        accounts: accounts,
        lockedThrough: settings['locked_through'] == null
            ? null
            : DateTime.tryParse(settings['locked_through'].toString())?.toLocal(),
        lockReason: settings['lock_reason']?.toString(),
      );

  @override
  List<Object?> get props => [accounts, lockedThrough, lockReason];
}
