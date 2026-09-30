import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../domain/bank_account.dart';

/// 캠퍼스별 설정. 송금 계좌는 campuses 행에 있다.
class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  static const _bankColumns = 'bank_name, account_number, account_holder';

  Future<BankAccount> fetchBankAccount(String campusId) async {
    final row = await _client
        .from('campuses')
        .select(_bankColumns)
        .eq('id', campusId)
        .maybeSingle();
    return BankAccount.fromSettings(
      row == null ? const {} : row.map((k, v) => MapEntry(k, v as String)),
    );
  }

  /// 캠퍼스 관리자는 자기 캠퍼스, 총괄 관리자는 모든 캠퍼스를 저장할 수 있다. (RLS)
  Future<void> saveBankAccount(String campusId, BankAccount account) => _client
      .from('campuses')
      .update({
        for (final e in account.toSettings().entries) e.key: e.value.trim(),
      })
      .eq('id', campusId)
      .expectAffected();
}
