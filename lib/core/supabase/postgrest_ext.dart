import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_exception.dart';

extension ExpectAffected on PostgrestFilterBuilder<dynamic> {
  /// update / delete 가 실제로 행을 바꿨는지 확인한다.
  ///
  /// RLS 에 막힌 update / delete 는 에러 없이 0행을 반환하므로,
  /// 반환된 행이 없으면 권한 없음 또는 대상 없음으로 간주한다.
  Future<void> expectAffected({String column = 'id'}) async {
    final rows = await select(column);
    if (rows.isEmpty) {
      throw const AppException('권한이 없거나 이미 삭제된 항목입니다.');
    }
  }
}
