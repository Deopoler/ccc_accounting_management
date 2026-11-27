import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/riverpod/cache_for.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../data/textbook_repository.dart';
import '../domain/order_round.dart';
import '../domain/textbook.dart';
import '../domain/textbook_category.dart';
import '../domain/textbook_order.dart';

final textbookRepositoryProvider = Provider<TextbookRepository>(
  (ref) => TextbookRepository(ref.watch(supabaseProvider)),
);

final textbooksProvider = FutureProvider.autoDispose
    .family<List<Textbook>, CampusScope>((ref, scope) async {
      final userId = ref.watch(currentUserIdProvider);
      final campusId = ref.watch(campusIdProvider(scope));
      if (userId == null || campusId == null) return const [];
      ref.cacheFor(defaultCacheDuration, campusScope: scope);
      return ref.watch(textbookRepositoryProvider).fetchTextbooks(campusId);
    });

final textbookCategoriesProvider = FutureProvider.autoDispose
    .family<List<TextbookCategory>, CampusScope>((ref, scope) async {
      final userId = ref.watch(currentUserIdProvider);
      final campusId = ref.watch(campusIdProvider(scope));
      if (userId == null || campusId == null) return const [];
      ref.cacheFor(defaultCacheDuration, campusScope: scope);
      return ref.watch(textbookRepositoryProvider).fetchCategories(campusId);
    });

/// 본인 캠퍼스의 이번 회차 (회원 화면).
final currentRoundProvider = FutureProvider.autoDispose<OrderRound?>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  final campusId = ref.watch(myCampusIdProvider);
  if (userId == null || campusId == null) return null;
  ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.member);
  return ref.watch(textbookRepositoryProvider).fetchCurrentRound();
});

/// 관리 중인 캠퍼스의 이번 회차. 마감된 회차 다음 회차 생성을 먼저 보장한다.
final adminCurrentRoundProvider = FutureProvider.autoDispose<OrderRound?>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  final campusId = ref.watch(adminCampusIdProvider);
  if (userId == null || campusId == null) return null;
  ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.admin);
  return ref
      .watch(textbookRepositoryProvider)
      .fetchCurrentRound(campusId: campusId);
});

/// 관리 중인 캠퍼스의 이번 회차와 모든 회차. 캠퍼스가 없으면 null.
final adminRoundsProvider = FutureProvider.autoDispose<RoundList?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final campusId = ref.watch(adminCampusIdProvider);
  if (userId == null || campusId == null) return null;
  ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.admin);
  // 이번 회차를 먼저 조회해야 마감된 회차 다음 회차가 만들어진다.
  final current = await ref.watch(adminCurrentRoundProvider.future);
  if (current == null) return null;
  final all = await ref.watch(textbookRepositoryProvider).fetchRounds(campusId);
  return RoundList(campusId: campusId, current: current, all: all);
});

final myOrdersProvider = FutureProvider.autoDispose<List<TextbookOrder>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  ref.cacheFor(defaultCacheDuration);
  return ref.watch(textbookRepositoryProvider).fetchMyOrders(userId);
});

final orderProvider = FutureProvider.autoDispose.family<TextbookOrder?, String>(
  (ref, orderId) async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return null;
    ref.cacheFor(defaultCacheDuration);
    return ref.watch(textbookRepositoryProvider).fetchOrder(orderId);
  },
);

/// 새 교재 신청 선택 수량. 탭을 오가도 유지되며 로그아웃 / 캠퍼스 변경 시 초기화된다.
final textbookCartProvider =
    NotifierProvider<TextbookCartNotifier, Map<String, int>>(
      TextbookCartNotifier.new,
    );

class TextbookCartNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    ref.watch(currentUserIdProvider);
    ref.watch(myCampusIdProvider);
    return const {};
  }

  void setQuantity(String textbookId, int quantity) {
    if (quantity <= 0) {
      if (!state.containsKey(textbookId)) return;
      final next = Map<String, int>.of(state)..remove(textbookId);
      state = Map.unmodifiable(next);
      return;
    }
    state = Map.unmodifiable({...state, textbookId: quantity});
  }

  void prune(Set<String> validIds) {
    if (state.isEmpty) return;
    if (state.keys.every(validIds.contains)) return;
    state = Map.unmodifiable({
      for (final entry in state.entries)
        if (validIds.contains(entry.key)) entry.key: entry.value,
    });
  }

  void clear() => state = const {};
}
