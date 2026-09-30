import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../data/settings_repository.dart';
import '../domain/bank_account.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseProvider)),
);

/// 캠퍼스의 송금 계좌. 회원 화면은 본인 캠퍼스, 관리자 설정은 관리 중인 캠퍼스.
final bankAccountProvider = FutureProvider.autoDispose
    .family<BankAccount, CampusScope>((ref, scope) async {
      final campusId = await ref.watch(campusIdProvider(scope).future);
      if (campusId == null) {
        return const BankAccount(bankName: '', accountNumber: '', holder: '');
      }
      return ref.watch(settingsRepositoryProvider).fetchBankAccount(campusId);
    });
