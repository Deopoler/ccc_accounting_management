import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/riverpod/cache_for.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
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

/// 총괄 관리자가 보는 피드백 목록 (최신순). 필터별로 캐시한다.
final feedbackListProvider = FutureProvider.autoDispose
    .family<List<FeedbackEntry>, FeedbackFilter>((ref, filter) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return const [];
      ref.cacheFor(defaultCacheDuration);
      return ref
          .watch(feedbackRepositoryProvider)
          .fetchFeedback(unresolvedOnly: filter == FeedbackFilter.unresolved);
    });
