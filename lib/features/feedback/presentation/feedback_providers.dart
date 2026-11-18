import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/feedback_repository.dart';
import '../domain/feedback_entry.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepository(ref.watch(supabaseProvider)),
);

/// 피드백 목록 필터.
enum FeedbackFilter {
  unresolved('미확인'),
  all('전체');

  const FeedbackFilter(this.label);

  final String label;
}

final feedbackFilterProvider =
    NotifierProvider.autoDispose<FeedbackFilterNotifier, FeedbackFilter>(
      FeedbackFilterNotifier.new,
    );

class FeedbackFilterNotifier extends Notifier<FeedbackFilter> {
  @override
  FeedbackFilter build() => FeedbackFilter.unresolved;

  void select(FeedbackFilter filter) => state = filter;
}

/// 총괄 관리자가 보는 피드백 목록 (최신순). 필터가 바뀌면 다시 불러온다.
final feedbackListProvider = FutureProvider.autoDispose<List<FeedbackEntry>>((
  ref,
) {
  final filter = ref.watch(feedbackFilterProvider);
  return ref
      .watch(feedbackRepositoryProvider)
      .fetchFeedback(unresolvedOnly: filter == FeedbackFilter.unresolved);
});
