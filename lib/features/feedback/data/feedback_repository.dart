import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../domain/feedback_entry.dart';

const _feedbackColumns =
    'id, user_id, content, created_at, resolved_at, resolved_by, '
    'profiles:profiles!feedback_user_id_fkey(name, student_id), '
    'campuses(name)';

class FeedbackRepository {
  FeedbackRepository(this._client);

  final SupabaseClient _client;

  /// 피드백을 보낸다. 보낸 사람 / 캠퍼스는 서버가 정하고, 너무 자주 보내면 서버가 막는다.
  Future<void> submit(String content) => _client.rpc<void>(
    'submit_feedback',
    params: {'p_content': content},
  );

  /// 최신순. 총괄 관리자만 조회된다. (RLS)
  Future<List<FeedbackEntry>> fetchFeedback({bool unresolvedOnly = false}) async {
    var query = _client.from('feedback').select(_feedbackColumns);
    if (unresolvedOnly) query = query.isFilter('resolved_at', null);
    final rows = await query.order('created_at', ascending: false).limit(200);
    return rows.map(FeedbackEntry.fromJson).toList();
  }

  /// 확인 처리 / 해제. 확인한 사람(resolved_by)은 서버가 기록한다.
  Future<void> setResolved(String id, {required bool resolved}) => _client
      .from('feedback')
      .update({
        'resolved_at': resolved ? DateTime.now().toUtc().toIso8601String() : null,
        if (!resolved) 'resolved_by': null,
      })
      .eq('id', id)
      .expectAffected();
}
