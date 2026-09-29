import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/domain/profile.dart';
import '../data/member_repository.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => MemberRepository(ref.watch(supabaseProvider)),
);

final membersProvider = FutureProvider.autoDispose<List<Profile>>(
  (ref) => ref.watch(memberRepositoryProvider).fetchMembers(),
);
