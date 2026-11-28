import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../../../core/utils/app_exception.dart';
import '../domain/order_round.dart';
import '../domain/textbook.dart';
import '../domain/textbook_category.dart';
import '../domain/textbook_order.dart';

/// 다른 곳에서 신청 상태가 먼저 바뀌어 요청을 적용하지 못한 경우.
class OrderStatusConflictException extends AppException {
  const OrderStatusConflictException([
    super.message = '신청 상태가 변경됨, 다시 확인해 주세요.',
  ]);
}

const _orderStatusConflictCode = 'P0009';
const _partialConflictMessage = '일부 적용됐을 수 있음, 새로고침 후 다시 확인해 주세요.';

/// 배송 처리 후 서버에 저장된 값.
typedef ShipmentState = ({
  bool isShipped,
  DateTime? shippedAt,
  DateTime? receivedAt,
  String? receivedBy,
});

const _orderColumns =
    'id, user_id, round_id, status, total_price, created_at, '
    'is_shipped, shipped_at, received_at, received_by, confirmed_deposit_id, '
    'order_rounds(id, starts_at, deadline), '
    'textbook_order_items(textbook_id, quantity, unit_price, textbooks(title))';

class TextbookRepository {
  TextbookRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------- 교재

  Future<List<Textbook>> fetchTextbooks(String campusId) async {
    final rows = await _client
        .from('textbooks')
        .select()
        .eq('campus_id', campusId)
        .order('sort_order')
        .order('title');
    return rows.map(Textbook.fromJson).toList();
  }

  Future<void> createTextbook(String campusId, TextbookInput input) => _client
      .from('textbooks')
      .insert({...input.toJson(), 'campus_id': campusId});

  Future<void> updateTextbook(String id, TextbookInput input) => _client
      .from('textbooks')
      .update(input.toJson())
      .eq('id', id)
      .expectAffected();

  Future<void> setTextbookActive(String id, {required bool isActive}) => _client
      .from('textbooks')
      .update({'is_active': isActive})
      .eq('id', id)
      .expectAffected();

  Future<void> deleteTextbook(String id) =>
      _client.from('textbooks').delete().eq('id', id).expectAffected();

  // ---------------------------------------------------------------- 카테고리

  Future<List<TextbookCategory>> fetchCategories(String campusId) async {
    final rows = await _client
        .from('textbook_categories')
        .select('id, name, sort_order')
        .eq('campus_id', campusId)
        .order('sort_order')
        .order('name');
    return rows.map(TextbookCategory.fromJson).toList();
  }

  /// 맨 뒤 순서로 추가한다.
  Future<void> createCategory(
    String campusId,
    String name, {
    required int sortOrder,
  }) => _client.from('textbook_categories').insert({
    'campus_id': campusId,
    'name': name.trim(),
    'sort_order': sortOrder,
  });

  Future<void> renameCategory(String id, String name) => _client
      .from('textbook_categories')
      .update({'name': name.trim()})
      .eq('id', id)
      .expectAffected();

  /// 교재가 남아 있으면 DB 가 거부한다(23503).
  Future<void> deleteCategory(String id) => _client
      .from('textbook_categories')
      .delete()
      .eq('id', id)
      .expectAffected();

  /// 한 카테고리 안의 교재를 목록 순서대로 sort_order 를 다시 매긴다.
  Future<void> reorderTextbooks(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _client
          .from('textbooks')
          .update({'sort_order': i})
          .eq('id', orderedIds[i])
          .expectAffected();
    }
  }

  /// 목록 순서대로 sort_order 를 다시 매긴다.
  Future<void> reorderCategories(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _client
          .from('textbook_categories')
          .update({'sort_order': i})
          .eq('id', orderedIds[i])
          .expectAffected();
    }
  }

  // ---------------------------------------------------------------- 회차

  /// 캠퍼스의 이번 회차. [campusId] 가 없으면 본인 캠퍼스.
  /// 지난 회차가 마감됐으면 서버가 다음 회차를 만든다.
  Future<OrderRound> fetchCurrentRound({String? campusId}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_order_round',
      params: {'p_campus_id': ?campusId},
    );
    if (rows.isEmpty) {
      throw const AppException('신청 회차를 불러오지 못했습니다. 다시 로그인해 주세요.');
    }
    return OrderRound.fromJson(rows.first as Map<String, dynamic>);
  }

  /// 캠퍼스의 모든 회차 (최신순). 미리 만든 다음 회차가 있으면 맨 앞이다.
  Future<List<OrderRound>> fetchRounds(String campusId) async {
    final rows = await _client
        .from('order_rounds')
        .select('id, starts_at, deadline')
        .eq('campus_id', campusId)
        .order('starts_at', ascending: false);
    return rows.map(OrderRound.fromJson).toList();
  }

  /// 이번 회차의 마감 일시를 바꾼다. 다음 회차부터는 이 마감에서 1주일씩 이어진다.
  Future<void> setRoundDeadline(String roundId, DateTime deadline) =>
      _client.rpc<void>(
        'admin_set_order_round_deadline',
        params: {
          'p_round_id': roundId,
          'p_deadline': deadline.toUtc().toIso8601String(),
        },
      );

  // ---------------------------------------------------------------- 회원 신청

  /// [quantities]: 교재 id → 수량. 가격/합계는 서버가 계산한다.
  Future<String> placeOrder(Map<String, int> quantities) async {
    final id = await _client.rpc<String>(
      'place_textbook_order',
      params: {'p_items': _items(quantities)},
    );
    return id;
  }

  Future<void> updateOrder(String orderId, Map<String, int> quantities) =>
      _client.rpc<void>(
        'update_textbook_order',
        params: {'p_order_id': orderId, 'p_items': _items(quantities)},
      );

  Future<void> cancelOrder(String orderId) => _client.rpc<void>(
    'cancel_textbook_order',
    params: {'p_order_id': orderId},
  );

  /// 배송된 본인 신청의 수령을 확인한다. 서버가 기록한 수령 시각을 돌려준다.
  Future<DateTime> confirmReceived(String orderId) async {
    final at = await _client.rpc<String>(
      'confirm_textbook_received',
      params: {'p_order_id': orderId},
    );
    return DateTime.parse(at);
  }

  /// 본인 신청 내역 (RLS 가 본인 것만 돌려준다).
  Future<List<TextbookOrder>> fetchMyOrders(String userId) async {
    final rows = await _client
        .from('textbook_orders')
        .select(_orderColumns)
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map(TextbookOrder.fromJson).toList();
  }

  Future<TextbookOrder?> fetchOrder(String orderId) async {
    final row = await _client
        .from('textbook_orders')
        .select(_orderColumns)
        .eq('id', orderId)
        .maybeSingle();
    return row == null ? null : TextbookOrder.fromJson(row);
  }

  // ---------------------------------------------------------------- 관리자

  /// 캠퍼스의 신청 현황. [roundId] 가 null 이면 모든 회차.
  Future<List<TextbookOrder>> fetchAllOrders(
    String campusId, {
    String? roundId,
  }) async {
    var query = _client
        .from('textbook_orders')
        // shipped_by 도 profiles 를 참조하므로 신청자 FK 를 지정한다.
        .select(
          '$_orderColumns, '
          'bank_deposits(status, matched_by), '
          'profiles:profiles!textbook_orders_user_id_fkey(student_id, name)',
        )
        .eq('campus_id', campusId);
    if (roundId != null) {
      query = query.eq('round_id', roundId);
    }
    final rows = await query.order('created_at', ascending: false);
    return rows.map(TextbookOrder.fromJson).toList();
  }

  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    required OrderStatus from,
  }) async {
    final rows = await _client
        .from('textbook_orders')
        .update({'status': status.name})
        .eq('id', orderId)
        .eq('status', from.name)
        .select('id');
    if (rows.length != 1) {
      throw const OrderStatusConflictException();
    }
  }

  /// 배송 완료 체크/해제. 배송 시각은 서버 트리거가 기록하고, 해제하면 수령 기록도 지워진다.
  /// 기대한 배송/수령 상태와 다르면 [OrderStatusConflictException] 을 던진다.
  Future<ShipmentState> setShipped(
    String orderId, {
    required bool shipped,
    required bool expectedReceived,
  }) async {
    var query = _client
        .from('textbook_orders')
        .update({'is_shipped': shipped})
        .eq('id', orderId)
        .eq('is_shipped', !shipped);
    query = expectedReceived
        ? query.not('received_at', 'is', null)
        : query.isFilter('received_at', null);
    final rows = await query.select(
      'is_shipped, shipped_at, received_at, received_by',
    );
    if (rows.isEmpty) {
      throw const OrderStatusConflictException();
    }
    final row = rows.first;
    DateTime? time(String key) =>
        row[key] == null ? null : DateTime.parse(row[key] as String);
    return (
      isShipped: row['is_shipped'] as bool,
      shippedAt: time('shipped_at'),
      receivedAt: time('received_at'),
      receivedBy: row['received_by'] as String?,
    );
  }

  /// 신청들을 각자 자기 회차의 이전([offset] = -1) / 다음(1) 회차로 옮긴다.
  /// 이번 회차의 다음 회차가 없으면 서버가 만든다. 하나라도 못 옮기면 아무것도 옮기지 않는다.
  Future<void> shiftOrders(List<String> orderIds, int offset) =>
      _client.rpc<void>(
        'admin_shift_textbook_orders',
        params: {'p_order_ids': orderIds, 'p_offset': offset},
      );

  // ---------------------------------------------------------------- 관리자 일괄 처리

  /// 여러 신청의 상태를 RPC 트랜잭션으로 한 번에 바꾼다. 하나라도 충돌하면 전부 롤백된다.
  Future<void> updateOrdersStatus(
    List<String> orderIds,
    OrderStatus status, {
    required Set<OrderStatus> from,
  }) async {
    final uniqueIds = orderIds.toSet().toList();
    if (uniqueIds.isEmpty) return;
    if (from.isEmpty) {
      throw const OrderStatusConflictException();
    }
    try {
      await _client.rpc<int>(
        'admin_update_order_status',
        params: {
          'p_ids': uniqueIds,
          'p_from': [for (final s in from) s.name],
          'p_to': status.name,
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == _orderStatusConflictCode) {
        throw const OrderStatusConflictException();
      }
      rethrow;
    }
  }

  /// 여러 신청의 배송 여부를 한 번에 바꾼다. 시각 기록 / 수령 초기화는 트리거가 한다.
  /// 배송 해제 시 [confirmedReceivedIds] 에 없는 행은 수령 전(`received_at is null`)만 갱신해
  /// 재조회 직후 회원이 확인한 수령 기록을 지우지 않는다.
  /// 이미 목표 배송 상태인 행은 성공으로 간주하고, 그 외 미갱신 행이 있으면 충돌 오류를 던진다.
  Future<void> setShippedMany(
    List<String> orderIds, {
    required bool shipped,
    Set<String> confirmedReceivedIds = const {},
  }) async {
    final uniqueIds = orderIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final updatedIds = <String>{};
    if (shipped) {
      final rows = await _client
          .from('textbook_orders')
          .update({'is_shipped': true})
          .inFilter('id', uniqueIds)
          .eq('is_shipped', false)
          .select('id');
      for (final row in rows) {
        updatedIds.add(row['id'] as String);
      }
    } else {
      final unreceivedIds = [
        for (final id in uniqueIds)
          if (!confirmedReceivedIds.contains(id)) id,
      ];
      final receivedIds = [
        for (final id in uniqueIds)
          if (confirmedReceivedIds.contains(id)) id,
      ];
      if (unreceivedIds.isNotEmpty) {
        final rows = await _client
            .from('textbook_orders')
            .update({'is_shipped': false})
            .inFilter('id', unreceivedIds)
            .eq('is_shipped', true)
            .isFilter('received_at', null)
            .select('id');
        for (final row in rows) {
          updatedIds.add(row['id'] as String);
        }
      }
      if (receivedIds.isNotEmpty) {
        final rows = await _client
            .from('textbook_orders')
            .update({'is_shipped': false})
            .inFilter('id', receivedIds)
            .eq('is_shipped', true)
            .select('id');
        for (final row in rows) {
          updatedIds.add(row['id'] as String);
        }
      }
    }

    final missingIds = [
      for (final id in uniqueIds)
        if (!updatedIds.contains(id)) id,
    ];
    if (missingIds.isEmpty) return;

    final alreadyAtTarget = await _client
        .from('textbook_orders')
        .select('id')
        .inFilter('id', missingIds)
        .eq('is_shipped', shipped);
    if (alreadyAtTarget.length != missingIds.length) {
      throw const OrderStatusConflictException(_partialConflictMessage);
    }
  }

  /// 관리자 수령 체크/해제. 서버가 기록한 수령 시각을 돌려준다. (해제하면 null)
  /// 배송된 신청만 체크할 수 있다. (서버 RPC 가 강제)
  Future<DateTime?> setReceived(
    String orderId, {
    required bool received,
  }) async {
    final at = await _client.rpc<String?>(
      'admin_set_textbook_received',
      params: {'p_order_id': orderId, 'p_received': received},
    );
    return at == null ? null : DateTime.parse(at);
  }

  List<Map<String, dynamic>> _items(Map<String, int> quantities) => [
    for (final e in quantities.entries)
      if (e.value > 0) {'textbook_id': e.key, 'quantity': e.value},
  ];
}
