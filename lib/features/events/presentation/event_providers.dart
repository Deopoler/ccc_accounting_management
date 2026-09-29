import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/event_repository.dart';
import '../domain/event.dart';

final eventRepositoryProvider = Provider<EventRepository>(
  (ref) => EventRepository(ref.watch(supabaseProvider)),
);

final eventsProvider = FutureProvider.autoDispose<List<Event>>(
  (ref) => ref.watch(eventRepositoryProvider).fetchEvents(),
);

final eventProvider = FutureProvider.autoDispose.family<Event?, String>(
  (ref, id) => ref.watch(eventRepositoryProvider).fetchEvent(id),
);

final eventSummariesProvider =
    FutureProvider.autoDispose<Map<String, EventSummary>>(
      (ref) => ref.watch(eventRepositoryProvider).fetchSummaries(),
    );

/// 이벤트 id → 내 송금 행 (없으면 대상 아님).
final myEventPaymentsProvider =
    FutureProvider.autoDispose<Map<String, EventPayment>>((ref) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return const {};
      return ref.watch(eventRepositoryProvider).fetchMyPayments(userId);
    });

/// 관리자: 이벤트별 송금 현황. 토글 시 목록을 다시 불러오지 않고 해당 행만 바꾼다.
final eventPaymentsProvider = AsyncNotifierProvider.autoDispose
    .family<EventPaymentsNotifier, List<EventPayment>, String>(
      EventPaymentsNotifier.new,
    );

class EventPaymentsNotifier extends AsyncNotifier<List<EventPayment>> {
  EventPaymentsNotifier(this.eventId);

  final String eventId;

  @override
  Future<List<EventPayment>> build() =>
      ref.watch(eventRepositoryProvider).fetchPayments(eventId);

  Future<void> setPaid(String paymentId, {required bool isPaid}) async {
    await ref.read(eventRepositoryProvider).setPaid(paymentId, isPaid: isPaid);
    final current = state.value;
    if (!ref.mounted || current == null) return;
    state = AsyncData([
      for (final p in current)
        p.id == paymentId ? p.copyWith(isPaid: isPaid) : p,
    ]);
  }

  Future<void> setAmountOverride(String paymentId, int? amount) async {
    await ref
        .read(eventRepositoryProvider)
        .setAmountOverride(paymentId, amount);
    final current = state.value;
    if (!ref.mounted || current == null) return;
    state = AsyncData([
      for (final p in current)
        p.id == paymentId ? p.copyWith(amountOverride: () => amount) : p,
    ]);
  }
}
