import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/riverpod/cache_for.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../deposits/presentation/deposit_providers.dart';
import '../../textbooks/data/textbook_repository.dart';
import '../../textbooks/domain/textbook_order.dart';
import '../../textbooks/presentation/textbook_providers.dart';

/// 조회 중 캠퍼스가 바뀌거나 화면이 닫혀 작업을 중단한 경우.
class StaleContextException extends AppException {
  const StaleContextException([
    super.message = '캠퍼스가 변경되어 작업을 취소했습니다. 다시 확인해 주세요.',
  ]);
}

/// 회차별 전체 신청 현황. 인자(회차 id)가 null 이면 모든 회차.
final adminOrdersProvider = AsyncNotifierProvider.autoDispose
    .family<AdminOrdersNotifier, List<TextbookOrder>, String?>(
      AdminOrdersNotifier.new,
    );

class AdminOrdersNotifier extends AsyncNotifier<List<TextbookOrder>> {
  AdminOrdersNotifier(this.roundId);

  final String? roundId;

  @override
  Future<List<TextbookOrder>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    final campusId = ref.watch(adminCampusIdProvider);
    if (userId == null || campusId == null) return const [];
    ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.admin);
    return ref
        .watch(textbookRepositoryProvider)
        .fetchAllOrders(campusId, roundId: roundId);
  }

  Set<String> _roundIdsFor(Iterable<String> orderIds) {
    final current = state.value;
    if (current == null) return const {};
    final ids = orderIds.toSet();
    return {
      for (final o in current)
        if (ids.contains(o.id)) o.roundId,
    };
  }

  void _invalidateOtherInstances([Iterable<String> affectedRoundIds = const []]) {
    if (roundId != null) {
      if (ref.exists(adminOrdersProvider(null))) {
        ref.invalidate(adminOrdersProvider(null));
      }
      return;
    }
    final targets = <String>{...affectedRoundIds};
    final rounds = ref.exists(adminRoundsProvider)
        ? ref.read(adminRoundsProvider).value
        : null;
    if (rounds != null) {
      for (final r in rounds.all) {
        targets.add(r.id);
      }
    }
    for (final id in targets) {
      if (ref.exists(adminOrdersProvider(id))) {
        ref.invalidate(adminOrdersProvider(id));
      }
    }
  }

  /// 캐시를 우회해 서버에서 최신 신청 목록을 다시 불러오고 로딩 깜빡임 없이 갱신한다.
  Future<List<TextbookOrder>> refetchFresh() async {
    final campusId = ref.read(adminCampusIdProvider);
    if (campusId == null) {
      throw const StaleContextException('캠퍼스가 선택되지 않아 작업을 진행할 수 없습니다.');
    }
    final repo = ref.read(textbookRepositoryProvider);
    final fresh = await repo.fetchAllOrders(campusId, roundId: roundId);
    if (!ref.mounted) {
      throw const StaleContextException();
    }
    final currentCampusId = ref.read(adminCampusIdProvider);
    if (currentCampusId != campusId) {
      throw const StaleContextException();
    }
    state = AsyncData(fresh);
    return fresh;
  }

  /// 서버에 상태를 저장하고, 성공하면 목록을 다시 불러오지 않고 해당 행만 바꾼다.
  Future<void> setStatus(
    String orderId,
    OrderStatus status, {
    required OrderStatus from,
  }) async {
    final affectedRounds = _roundIdsFor([orderId]);
    try {
      await ref
          .read(textbookRepositoryProvider)
          .updateOrderStatus(orderId, status, from: from);
    } on OrderStatusConflictException {
      if (ref.mounted) {
        _invalidateOtherInstances(affectedRounds);
        ref.invalidate(unpaidLinkTargetsProvider);
        try {
          await refetchFresh();
        } on StaleContextException {
          // 캠퍼스가 바뀌었으면 이전 캠퍼스 상태를 덮어쓰지 않는다.
        } catch (_) {
          if (ref.mounted) ref.invalidateSelf();
        }
      }
      rethrow;
    }
    if (!ref.mounted) return;
    _invalidateOtherInstances(affectedRounds);
    ref.invalidate(unpaidLinkTargetsProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final o in current) o.id == orderId ? o.copyWith(status: status) : o,
    ]);
  }

  /// 배송 완료 체크/해제. 서버가 기록한 시각으로 해당 행만 바꾼다.
  Future<void> setShipped(
    String orderId, {
    required bool shipped,
    required bool expectedReceived,
  }) async {
    final affectedRounds = _roundIdsFor([orderId]);
    final ShipmentState saved;
    try {
      saved = await ref
          .read(textbookRepositoryProvider)
          .setShipped(
            orderId,
            shipped: shipped,
            expectedReceived: expectedReceived,
          );
    } on OrderStatusConflictException {
      if (ref.mounted) {
        _invalidateOtherInstances(affectedRounds);
        try {
          await refetchFresh();
        } on StaleContextException {
          // 캠퍼스가 바뀌었으면 이전 캠퍼스 상태를 덮어쓰지 않는다.
        } catch (_) {
          if (ref.mounted) ref.invalidateSelf();
        }
      }
      rethrow;
    }
    if (!ref.mounted) return;
    _invalidateOtherInstances(affectedRounds);
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final o in current)
        o.id == orderId
            ? o.copyWith(
                isShipped: saved.isShipped,
                shippedAt: () => saved.shippedAt,
                receivedAt: () => saved.receivedAt,
                receivedBy: () => saved.receivedBy,
              )
            : o,
    ]);
  }

  /// 일괄 처리. 여러 행이 바뀌므로 끝나면(실패해도) 목록을 다시 불러온다.
  Future<void> bulkSetPaid(
    List<String> ids, {
    required bool paid,
    Set<OrderStatus>? from,
  }) => _bulk(
    ids,
    () => ref
        .read(textbookRepositoryProvider)
        .updateOrdersStatus(
          ids,
          paid ? OrderStatus.paid : OrderStatus.requested,
          from: from ?? {paid ? OrderStatus.requested : OrderStatus.paid},
        ),
    affectsUnpaid: true,
  );

  Future<void> bulkSetShipped(
    List<String> ids, {
    required bool shipped,
    Set<String> confirmedReceivedIds = const {},
  }) => _bulk(
    ids,
    () => ref
        .read(textbookRepositoryProvider)
        .setShippedMany(
          ids,
          shipped: shipped,
          confirmedReceivedIds: confirmedReceivedIds,
        ),
  );

  /// 수령은 행마다 RPC 로 처리한다. (서버가 배송 여부 / 권한을 행마다 검사)
  Future<void> bulkSetReceived(List<String> ids, {required bool received}) =>
      _bulk(ids, () async {
        final repo = ref.read(textbookRepositoryProvider);
        for (final id in ids) {
          await repo.setReceived(id, received: received);
        }
      });

  Future<void> _bulk(
    List<String> ids,
    Future<void> Function() action, {
    bool affectsUnpaid = false,
  }) async {
    final affectedRounds = _roundIdsFor(ids);
    try {
      await action();
    } finally {
      if (ref.mounted) {
        _invalidateOtherInstances(affectedRounds);
        if (affectsUnpaid) ref.invalidate(unpaidLinkTargetsProvider);
      }
      // 다시 불러오기가 실패해도 원래 오류를 가리지 않게 한다.
      try {
        if (ref.mounted) {
          await refetchFresh();
        }
      } on StaleContextException {
        // 캠퍼스 전환이나 해제 시 상태를 덮어쓰지 않는다.
      } catch (_) {
        if (ref.mounted) ref.invalidateSelf();
      }
    }
  }

  /// 관리자 수령 체크/해제. 서버가 기록한 시각으로 해당 행만 바꾼다.
  Future<void> setReceived(String orderId, {required bool received}) async {
    final affectedRounds = _roundIdsFor([orderId]);
    final at = await ref
        .read(textbookRepositoryProvider)
        .setReceived(orderId, received: received);
    if (!ref.mounted) return;
    _invalidateOtherInstances(affectedRounds);
    final adminId = ref.read(currentUserIdProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final o in current)
        o.id == orderId
            ? o.copyWith(
                receivedAt: () => at,
                // 이미 수령된 건이면 서버가 기존 확인자를 유지한다.
                receivedBy: () => at == null
                    ? null
                    : o.receivedAt != null
                    ? o.receivedBy
                    : adminId,
              )
            : o,
    ]);
  }
}
