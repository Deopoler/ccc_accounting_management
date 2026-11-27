import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/riverpod/cache_for.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../data/member_repository.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => MemberRepository(ref.watch(supabaseProvider)),
);

final membersProvider = FutureProvider.autoDispose<List<Profile>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final campusId = ref.watch(adminCampusIdProvider);
  if (userId == null || campusId == null) return const [];
  ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.admin);
  return ref.watch(memberRepositoryProvider).fetchMembers(campusId);
});
