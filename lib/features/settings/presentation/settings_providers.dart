import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/settings_repository.dart';
import '../domain/bank_account.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseProvider)),
);

final bankAccountProvider = FutureProvider.autoDispose<BankAccount>(
  (ref) => ref.watch(settingsRepositoryProvider).fetchBankAccount(),
);
