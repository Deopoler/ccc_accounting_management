import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/domain/profile.dart';
import '../../campus/presentation/campus_providers.dart';
import '../data/member_repository.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => MemberRepository(ref.watch(supabaseProvider)),
);

final membersProvider = FutureProvider.autoDispose<List<Profile>>((ref) async {
  final campusId = await ref.watch(activeCampusIdProvider.future);
  if (campusId == null) return const [];
  return ref.watch(memberRepositoryProvider).fetchMembers(campusId);
});
