import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../domain/bank_account.dart';

class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, String>> _fetchAll() async {
    final rows = await _client.from('app_settings').select('key, value');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<BankAccount> fetchBankAccount() async =>
      BankAccount.fromSettings(await _fetchAll());

  /// 키는 마이그레이션에서 미리 만들어 두므로 value 만 갱신한다.
  Future<void> saveBankAccount(BankAccount account) async {
    for (final e in account.toSettings().entries) {
      await _client
          .from('app_settings')
          .update({'value': e.value.trim()})
          .eq('key', e.key)
          .expectAffected(column: 'key');
    }
  }
}
