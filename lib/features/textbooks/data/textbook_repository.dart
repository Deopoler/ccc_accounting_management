import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../../../core/utils/app_exception.dart';
import '../domain/order_round.dart';
import '../domain/textbook.dart';
import '../domain/textbook_category.dart';
import '../domain/textbook_order.dart';

/// 배송 처리 후 서버에 저장된 값.
typedef ShipmentState = ({
  bool isShipped,
  DateTime? shippedAt,
  DateTime? receivedAt,
  String? receivedBy,
});

const _orderColumns =
    'id, user_id, round_id, status, total_price, created_at, '
    'is_shipped, shipped_at, received_at, received_by, '
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

  /// 이번 회차 다음 회차를 만든다. (이미 있으면 그 회차) 신청을 다음 회차로 옮길 때 쓴다.
  Future<OrderRound> createNextRound(String campusId) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'admin_create_next_order_round',
      params: {'p_campus_id': campusId},
    );
    return OrderRound.fromJson(row);
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
          'profiles:profiles!textbook_orders_user_id_fkey(student_id, name)',
        )
        .eq('campus_id', campusId);
    if (roundId != null) {
      query = query.eq('round_id', roundId);
    }
    final rows = await query.order('created_at', ascending: false);
    return rows.map(TextbookOrder.fromJson).toList();
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) => _client
      .from('textbook_orders')
      .update({'status': status.name})
      .eq('id', orderId)
      .expectAffected();

  /// 배송 완료 체크/해제. 배송 시각은 서버 트리거가 기록하고, 해제하면 수령 기록도 지워진다.
  /// 서버에 저장된 배송/수령 값을 돌려준다.
  Future<ShipmentState> setShipped(
    String orderId, {
    required bool shipped,
  }) async {
    final rows = await _client
        .from('textbook_orders')
        .update({'is_shipped': shipped})
        .eq('id', orderId)
        .select('is_shipped, shipped_at, received_at, received_by');
    if (rows.isEmpty) {
      throw const AppException('권한이 없거나 이미 삭제된 항목입니다.');
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

  /// 신청을 같은 캠퍼스의 다른 회차로 옮긴다. 신청 날짜와 상관없다.
  Future<void> moveOrder(String orderId, String roundId) => _client.rpc<void>(
    'admin_move_textbook_order',
    params: {'p_order_id': orderId, 'p_round_id': roundId},
  );

  // ---------------------------------------------------------------- 관리자 일괄 처리

  /// 여러 신청의 상태를 한 번에 바꾼다. (한 번의 update 라 전부 성공하거나 전부 실패)
  Future<void> updateOrdersStatus(List<String> orderIds, OrderStatus status) =>
      _updateMany(orderIds, {'status': status.name});

  /// 여러 신청의 배송 여부를 한 번에 바꾼다. 시각 기록 / 수령 초기화는 트리거가 한다.
  Future<void> setShippedMany(List<String> orderIds, {required bool shipped}) =>
      _updateMany(orderIds, {'is_shipped': shipped});

  Future<void> _updateMany(
    List<String> orderIds,
    Map<String, Object> values,
  ) async {
    if (orderIds.isEmpty) return;
    final rows = await _client
        .from('textbook_orders')
        .update(values)
        .inFilter('id', orderIds)
        .select('id');
    if (rows.length != orderIds.length) {
      throw const AppException('일부 신청을 처리하지 못했습니다. 목록을 새로 불러와 확인해 주세요.');
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
