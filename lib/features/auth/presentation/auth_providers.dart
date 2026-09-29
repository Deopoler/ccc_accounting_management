import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/auth_repository.dart';
import '../domain/profile.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// 로그인한 사용자 id (없으면 null). 로그인/로그아웃 시 갱신된다.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUserId;
});

/// 로그인한 사용자의 프로필. 로그아웃 상태면 null.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(authRepositoryProvider).fetchProfile(userId);
});

/// 화면 표시용 관리자 여부. 실제 권한은 서버(RLS)가 강제한다.
final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(currentProfileProvider).value?.isAdmin ?? false,
);
