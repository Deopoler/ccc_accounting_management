import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/riverpod/cache_for.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../data/settings_repository.dart';
import '../domain/bank_account.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseProvider)),
);

/// 캠퍼스의 송금 계좌. 회원 화면은 본인 캠퍼스, 관리자 설정은 관리 중인 캠퍼스.
final bankAccountProvider = FutureProvider.autoDispose
    .family<BankAccount, CampusScope>((ref, scope) async {
      final userId = ref.watch(currentUserIdProvider);
      final campusId = ref.watch(campusIdProvider(scope));
      if (userId == null || campusId == null) {
        return const BankAccount(bankName: '', accountNumber: '', holder: '');
      }
      ref.cacheFor(defaultCacheDuration, campusScope: scope);
      return ref.watch(settingsRepositoryProvider).fetchBankAccount(campusId);
    });
