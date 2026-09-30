import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../data/settings_repository.dart';
import '../domain/bank_account.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseProvider)),
);

/// 지금 캠퍼스의 송금 계좌.
final bankAccountProvider = FutureProvider.autoDispose<BankAccount>((
  ref,
) async {
  final campusId = await ref.watch(activeCampusIdProvider.future);
  if (campusId == null) {
    return const BankAccount(bankName: '', accountNumber: '', holder: '');
  }
  return ref.watch(settingsRepositoryProvider).fetchBankAccount(campusId);
});
