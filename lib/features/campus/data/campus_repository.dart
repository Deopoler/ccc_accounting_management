import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/campus.dart';

class CampusRepository {
  CampusRepository(this._client);

  final SupabaseClient _client;

  /// 로그인 / 가입 화면의 캠퍼스 목록. 로그인 전에도 호출할 수 있다. (이름 / 코드 / 도메인만)
  Future<List<Campus>> listCampuses() async {
    final rows = await _client.rpc<List<dynamic>>('list_campuses');
    return rows.cast<Map<String, dynamic>>().map(Campus.fromJson).toList();
  }
}
