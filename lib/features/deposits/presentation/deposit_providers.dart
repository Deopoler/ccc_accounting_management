import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../data/deposit_repository.dart';
import '../domain/bank_deposit.dart';

final depositRepositoryProvider = Provider<DepositRepository>(
  (ref) => DepositRepository(ref.watch(supabaseProvider)),
);

final depositSettingsProvider =
    FutureProvider.autoDispose<CampusDepositSettings?>((ref) async {
      final campusId = await ref.watch(adminCampusIdProvider.future);
      if (campusId == null) return null;
      return ref.watch(depositRepositoryProvider).fetchSettings(campusId);
    });

final bankDepositsProvider = FutureProvider.autoDispose<List<BankDeposit>>((
  ref,
) async {
  final campusId = await ref.watch(adminCampusIdProvider.future);
  if (campusId == null) return const [];
  return ref.watch(depositRepositoryProvider).fetchDeposits(campusId);
});

final unpaidLinkTargetsProvider =
    FutureProvider.autoDispose<UnpaidLinkTargets>((ref) async {
      final campusId = await ref.watch(adminCampusIdProvider.future);
      if (campusId == null) return UnpaidLinkTargets.empty;
      return ref
          .watch(depositRepositoryProvider)
          .fetchUnpaidLinkTargets(campusId);
    });
