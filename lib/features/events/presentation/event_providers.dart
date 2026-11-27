import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/riverpod/cache_for.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../deposits/presentation/deposit_providers.dart';
import '../data/event_repository.dart';
import '../domain/event.dart';

final eventRepositoryProvider = Provider<EventRepository>(
  (ref) => EventRepository(ref.watch(supabaseProvider)),
);

final eventsProvider = FutureProvider.autoDispose
    .family<List<Event>, CampusScope>((ref, scope) async {
      final userId = ref.watch(currentUserIdProvider);
      final campusId = ref.watch(campusIdProvider(scope));
      if (userId == null || campusId == null) return const [];
      ref.cacheFor(defaultCacheDuration, campusScope: scope);
      return ref.watch(eventRepositoryProvider).fetchEvents(campusId);
    });

final eventProvider = FutureProvider.autoDispose.family<Event?, String>((
  ref,
  id,
) async {
  final userId = ref.watch(currentUserIdProvider);
  final campusId = ref.watch(adminCampusIdProvider);
  if (userId == null || campusId == null) return null;
  ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.admin);
  final event = await ref.watch(eventRepositoryProvider).fetchEvent(id);
  if (event == null || event.campusId != campusId) return null;
  return event;
});

final eventSummariesProvider =
    FutureProvider.autoDispose<Map<String, EventSummary>>((ref) async {
      final userId = ref.watch(currentUserIdProvider);
      final campusId = ref.watch(adminCampusIdProvider);
      if (userId == null || campusId == null) return const {};
      ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.admin);
      return ref.watch(eventRepositoryProvider).fetchSummaries();
    });

/// 이벤트 id → 내 송금 행 (없으면 대상 아님).
final myEventPaymentsProvider =
    FutureProvider.autoDispose<Map<String, EventPayment>>((ref) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return const {};
      ref.cacheFor(defaultCacheDuration);
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
  Future<List<EventPayment>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    final campusId = ref.watch(adminCampusIdProvider);
    if (userId == null || campusId == null) return const [];
    ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.admin);
    (Object, StackTrace)? paymentsError;
    final eventFuture = ref.read(eventProvider(eventId).future);
    final paymentsFuture = ref
        .watch(eventRepositoryProvider)
        .fetchPayments(eventId)
        .then<List<EventPayment>?>(
          (v) => v,
          onError: (Object err, StackTrace st) {
            paymentsError = (err, st);
            return null;
          },
        );
    final event = await eventFuture;
    if (event == null || event.campusId != campusId) return const [];
    final payments = await paymentsFuture;
    if (paymentsError case (final err, final st)) {
      Error.throwWithStackTrace(err, st);
    }
    return payments ?? const [];
  }

  Future<void> setPaid(String paymentId, {required bool isPaid}) async {
    await ref.read(eventRepositoryProvider).setPaid(paymentId, isPaid: isPaid);
    if (!ref.mounted) return;
    ref.invalidate(unpaidLinkTargetsProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final p in current)
        p.id == paymentId ? p.copyWith(isPaid: isPaid) : p,
    ]);
  }

  Future<void> setAmountOverride(String paymentId, int? amount) async {
    await ref
        .read(eventRepositoryProvider)
        .setAmountOverride(paymentId, amount);
    if (!ref.mounted) return;
    ref.invalidate(unpaidLinkTargetsProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final p in current)
        p.id == paymentId ? p.copyWith(amountOverride: () => amount) : p,
    ]);
  }
}
