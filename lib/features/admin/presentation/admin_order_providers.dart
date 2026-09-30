import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
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
  Future<List<TextbookOrder>> build() => ref
      .watch(textbookRepositoryProvider)
      .fetchAllOrders(roundStart: roundStart);

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
