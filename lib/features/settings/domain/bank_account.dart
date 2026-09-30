/// 송금 계좌 정보 (campuses 의 bank_name / account_number / account_holder).
class BankAccount {
  const BankAccount({
    required this.bankName,
    required this.accountNumber,
    required this.holder,
  });

  factory BankAccount.fromSettings(Map<String, String> settings) => BankAccount(
    bankName: settings[bankNameKey] ?? '',
    accountNumber: settings[accountNumberKey] ?? '',
    holder: settings[holderKey] ?? '',
  );

  static const bankNameKey = 'bank_name';
  static const accountNumberKey = 'account_number';
  static const holderKey = 'account_holder';

  final String bankName;
  final String accountNumber;
  final String holder;

  bool get isConfigured => bankName.isNotEmpty && accountNumber.isNotEmpty;

  Map<String, String> toSettings() => {
    bankNameKey: bankName,
    accountNumberKey: accountNumber,
    holderKey: holder,
  };
}
