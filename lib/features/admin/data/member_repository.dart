import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/domain/profile.dart';

class MemberRepository {
  MemberRepository(this._client);

  final SupabaseClient _client;

  /// 전체 회원 (관리자만 전체가 조회된다 - RLS).
  Future<List<Profile>> fetchMembers() async {
    final rows = await _client.from('profiles').select().order('student_id');
    return rows.map(Profile.fromJson).toList();
  }

  /// 가입 승인. 승인되면 DB 트리거가 진행 중인 이벤트의 송금 대상으로 등록한다.
  Future<void> approve(Iterable<String> userIds) async {
    final ids = userIds.toList();
    if (ids.isEmpty) return;
    final rows = await _client
        .from('profiles')
        .update({'is_approved': true})
        .inFilter('id', ids)
        .select('id');
    if (rows.length != ids.length) {
      throw const AppException('일부 회원을 승인하지 못했습니다. 새로고침 후 다시 시도해 주세요.');
    }
  }

  Future<void> setRole(String userId, UserRole role) => _client
      .from('profiles')
      .update({'role': role.name})
      .eq('id', userId)
      .expectAffected();

  // ---------------------------------------------------------------- Edge Function
  // service role 이 필요한 작업. 호출자가 관리자인지는 함수가 서버에서 검증한다.

  /// 기본 비밀번호로 초기화하고 다음 로그인 시 변경을 강제한다.
  Future<String> resetPassword(String userId) =>
      _invokeAdmin('reset_password', userId);

  /// 승인 대기 중인 가입 신청을 거절한다. (계정 삭제)
  Future<String> rejectSignup(String userId) =>
      _invokeAdmin('reject_signup', userId);

  Future<String> _invokeAdmin(String action, String userId) async {
    final res = await _client.functions.invoke(
      'admin-members',
      body: {'action': action, 'user_id': userId},
    );
    final data = res.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return '처리했습니다.';
  }
}
