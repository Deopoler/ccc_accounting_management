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
});

const _orderColumns =
    'id, user_id, round_start, status, total_price, created_at, '
    'is_shipped, shipped_at, received_at, '
    'textbook_order_items(textbook_id, quantity, unit_price, textbooks(title))';

class TextbookRepository {
  TextbookRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------- 교재

  Future<List<Textbook>> fetchTextbooks() async {
    final rows = await _client
        .from('textbooks')
        .select()
        .order('sort_order')
        .order('title');
    return rows.map(Textbook.fromJson).toList();
  }

  Future<void> createTextbook(TextbookInput input) =>
      _client.from('textbooks').insert(input.toJson());

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

  Future<List<TextbookCategory>> fetchCategories() async {
    final rows = await _client
        .from('textbook_categories')
        .select('id, name, sort_order')
        .order('sort_order')
        .order('name');
    return rows.map(TextbookCategory.fromJson).toList();
  }

  /// 맨 뒤 순서로 추가한다.
  Future<void> createCategory(String name, {required int sortOrder}) => _client
      .from('textbook_categories')
      .insert({'name': name.trim(), 'sort_order': sortOrder});

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

  Future<OrderRound> fetchCurrentRound() async {
    final rows = await _client.rpc<List<dynamic>>('get_order_round');
    return OrderRound.fromJson(rows.first as Map<String, dynamic>);
  }

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

  /// 전체 신청 현황. [roundStart] 가 null 이면 모든 회차.
  Future<List<TextbookOrder>> fetchAllOrders({DateTime? roundStart}) async {
    var query = _client
        .from('textbook_orders')
        .select('$_orderColumns, profiles(student_id, name)');
    if (roundStart != null) {
      query = query.eq('round_start', toDateOnly(roundStart));
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
        .select('is_shipped, shipped_at, received_at');
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
    );
  }

  List<Map<String, dynamic>> _items(Map<String, int> quantities) => [
    for (final e in quantities.entries)
      if (e.value > 0) {'textbook_id': e.key, 'quantity': e.value},
  ];
}
