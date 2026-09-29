import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_exception.dart';
import '../domain/credentials.dart';
import '../domain/profile.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Stream<AuthState> authStateChanges() => _auth.onAuthStateChange;

  String? get currentUserId => _auth.currentSession?.user.id;

  Future<void> signIn({
    required String studentId,
    required String password,
  }) async {
    await _auth.signInWithPassword(
      email: studentIdToEmail(studentId),
      password: password,
    );
  }

  /// 가입. 프로필은 DB 트리거가 "승인 대기" 상태로 만든다.
  Future<void> signUp({
    required String studentId,
    required String name,
    required String password,
  }) async {
    final res = await _auth.signUp(
      email: studentIdToEmail(studentId),
      password: password,
      data: {'name': name.trim()},
    );
    if (res.session == null) {
      // Supabase 의 "Confirm email" 이 켜져 있으면 세션이 없다. (가상 이메일이라 확인 불가)
      throw const AppException(
        '가입은 되었지만 로그인할 수 없습니다. 회계 담당자에게 문의해 주세요. (이메일 확인 설정)',
      );
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<Profile?> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// 비밀번호를 변경한다. [currentPassword] 가 있으면 먼저 현재 비밀번호를 확인한다.
  ///
  /// 비밀번호가 바뀌면 DB 트리거가 `must_change_password` 를 해제한다.
  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword != null) {
      final email = _auth.currentUser?.email;
      if (email == null) throw const AppException('로그인이 필요합니다.');
      try {
        await _auth.signInWithPassword(email: email, password: currentPassword);
      } on AuthException catch (e) {
        if (e.message.toLowerCase().contains('invalid login credentials')) {
          throw const AppException('현재 비밀번호가 올바르지 않습니다.');
        }
        rethrow;
      }
    }
    await _auth.updateUser(UserAttributes(password: newPassword));
  }
}
