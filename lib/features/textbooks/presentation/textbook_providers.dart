import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final campusId = await ref.watch(campusIdProvider(scope).future);
      if (campusId == null) return const [];
      return ref.watch(textbookRepositoryProvider).fetchTextbooks(campusId);
    });

final textbookCategoriesProvider = FutureProvider.autoDispose
    .family<List<TextbookCategory>, CampusScope>((ref, scope) async {
      final campusId = await ref.watch(campusIdProvider(scope).future);
      if (campusId == null) return const [];
      return ref.watch(textbookRepositoryProvider).fetchCategories(campusId);
    });

/// 본인 캠퍼스의 이번 회차 (회원 화면).
final currentRoundProvider = FutureProvider.autoDispose<OrderRound>(
  (ref) => ref.watch(textbookRepositoryProvider).fetchCurrentRound(),
);

/// 관리 중인 캠퍼스의 이번 회차와 모든 회차. 캠퍼스가 없으면 null.
final adminRoundsProvider = FutureProvider.autoDispose<RoundList?>((ref) async {
  final campusId = await ref.watch(adminCampusIdProvider.future);
  if (campusId == null) return null;
  final repo = ref.watch(textbookRepositoryProvider);
  // 이번 회차를 먼저 조회해야 마감된 회차 다음 회차가 만들어진다.
  final current = await repo.fetchCurrentRound(campusId: campusId);
  return RoundList(
    campusId: campusId,
    current: current,
    all: await repo.fetchRounds(campusId),
  );
});

final myOrdersProvider = FutureProvider.autoDispose<List<TextbookOrder>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(textbookRepositoryProvider).fetchMyOrders(userId);
});

final orderProvider = FutureProvider.autoDispose.family<TextbookOrder?, String>(
  (ref, orderId) => ref.watch(textbookRepositoryProvider).fetchOrder(orderId),
);
