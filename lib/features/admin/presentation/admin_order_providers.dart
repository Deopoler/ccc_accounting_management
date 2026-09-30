import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../textbooks/domain/textbook_order.dart';
import '../../textbooks/presentation/textbook_providers.dart';

/// 회차별 전체 신청 현황. 인자가 null 이면 모든 회차.
final adminOrdersProvider = AsyncNotifierProvider.autoDispose
    .family<AdminOrdersNotifier, List<TextbookOrder>, DateTime?>(
      AdminOrdersNotifier.new,
    );

class AdminOrdersNotifier extends AsyncNotifier<List<TextbookOrder>> {
  AdminOrdersNotifier(this.roundStart);

  final DateTime? roundStart;

  @override
  Future<List<TextbookOrder>> build() async {
    final campusId = await ref.watch(activeCampusIdProvider.future);
    if (campusId == null) return const [];
    return ref
        .watch(textbookRepositoryProvider)
        .fetchAllOrders(campusId, roundStart: roundStart);
  }

  /// 서버에 상태를 저장하고, 성공하면 목록을 다시 불러오지 않고 해당 행만 바꾼다.
  Future<void> setStatus(String orderId, OrderStatus status) async {
    await ref
        .read(textbookRepositoryProvider)
        .updateOrderStatus(orderId, status);
    final current = state.value;
    if (!ref.mounted || current == null) return;
    state = AsyncData([
      for (final o in current) o.id == orderId ? o.copyWith(status: status) : o,
    ]);
  }

  /// 배송 완료 체크/해제. 서버가 기록한 시각으로 해당 행만 바꾼다.
  Future<void> setShipped(String orderId, {required bool shipped}) async {
    final saved = await ref
        .read(textbookRepositoryProvider)
        .setShipped(orderId, shipped: shipped);
    final current = state.value;
    if (!ref.mounted || current == null) return;
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
  Future<void> bulkSetPaid(List<String> ids, {required bool paid}) => _bulk(
    () => ref
        .read(textbookRepositoryProvider)
        .updateOrdersStatus(
          ids,
          paid ? OrderStatus.paid : OrderStatus.requested,
        ),
  );

  Future<void> bulkSetShipped(List<String> ids, {required bool shipped}) =>
      _bulk(
        () => ref
            .read(textbookRepositoryProvider)
            .setShippedMany(ids, shipped: shipped),
      );

  /// 수령은 행마다 RPC 로 처리한다. (서버가 배송 여부 / 권한을 행마다 검사)
  Future<void> bulkSetReceived(List<String> ids, {required bool received}) =>
      _bulk(() async {
        final repo = ref.read(textbookRepositoryProvider);
        for (final id in ids) {
          await repo.setReceived(id, received: received);
        }
      });

  Future<void> _bulk(Future<void> Function() action) async {
    try {
      await action();
    } finally {
      // 다시 불러오기가 실패해도 원래 오류를 가리지 않게 한다.
      try {
        final campusId = await ref.read(activeCampusIdProvider.future);
        final repo = ref.read(textbookRepositoryProvider);
        final fresh = campusId == null
            ? const <TextbookOrder>[]
            : await repo.fetchAllOrders(campusId, roundStart: roundStart);
        if (ref.mounted) state = AsyncData(fresh);
      } catch (_) {
        if (ref.mounted) ref.invalidateSelf();
      }
    }
  }

  /// 관리자 수령 체크/해제. 서버가 기록한 시각으로 해당 행만 바꾼다.
  Future<void> setReceived(String orderId, {required bool received}) async {
    final at = await ref
        .read(textbookRepositoryProvider)
        .setReceived(orderId, received: received);
    final adminId = ref.read(currentUserIdProvider);
    final current = state.value;
    if (!ref.mounted || current == null) return;
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
