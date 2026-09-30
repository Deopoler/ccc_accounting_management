import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../domain/campus.dart';

class CampusRepository {
  CampusRepository(this._client);

  final SupabaseClient _client;

  /// 로그인 / 가입 화면의 캠퍼스 목록. 로그인 전에도 호출할 수 있다. (이름 / 코드 / 도메인만)
  Future<List<Campus>> listCampuses() async {
    final rows = await _client.rpc<List<dynamic>>('list_campuses');
    return rows.cast<Map<String, dynamic>>().map(Campus.fromJson).toList();
  }

  /// 캠퍼스 추가 (총괄 관리자만 - RLS). 이메일 도메인은 서버가 코드로 정한다.
  Future<void> createCampus({required String code, required String name}) =>
      _client.from('campuses').insert({
        'code': code.trim().toLowerCase(),
        'name': name.trim(),
      });

  /// 캠퍼스 이름 변경. 코드 / 로그인 아이디는 바뀌지 않는다.
  Future<void> renameCampus(String id, String name) => _client
      .from('campuses')
      .update({'name': name.trim()})
      .eq('id', id)
      .expectAffected();
}

final _campusCodePattern = RegExp(r'^[a-z][a-z0-9]{1,19}$');

/// 캠퍼스 코드 검사 (서버 check 제약과 같은 규칙).
String? validateCampusCode(String? value) {
  final v = value?.trim().toLowerCase() ?? '';
  if (v.isEmpty) return '코드를 입력해 주세요.';
  if (!_campusCodePattern.hasMatch(v)) {
    return '영문 소문자로 시작하는 영문 소문자 / 숫자 2~20자';
  }
  return null;
}
