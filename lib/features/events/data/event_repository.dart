import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/postgrest_ext.dart';
import '../domain/event.dart';

const _paymentColumns =
    'id, event_id, user_id, is_paid, paid_at, amount_override, '
    'member:profiles!event_payments_user_id_fkey(student_id, name)';

class EventRepository {
  EventRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------- 이벤트

  /// 화면 표시 순서는 [sortEventsForDisplay] 참고.
  Future<List<Event>> fetchEvents(String campusId) async {
    final rows = await _client
        .from('events')
        .select()
        .eq('campus_id', campusId)
        .order('created_at', ascending: false);
    return sortEventsForDisplay(rows.map(Event.fromJson), DateTime.now());
  }

  Future<Event?> fetchEvent(String id) async {
    final row = await _client
        .from('events')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Event.fromJson(row);
  }

  /// 이벤트를 만들고 id 를 돌려준다. 송금 대상은 관리자가 따로 추가한다.
  Future<String> createEvent(String campusId, EventInput input) async {
    final row = await _client
        .from('events')
        .insert({...input.toJson(), 'campus_id': campusId})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateEvent(String id, EventInput input) => _client
      .from('events')
      .update(input.toJson())
      .eq('id', id)
      .expectAffected();

  Future<void> deleteEvent(String id) =>
      _client.from('events').delete().eq('id', id).expectAffected();

  /// 이벤트 id → 송금 요약. 관리자는 전체, 회원은 본인 행만 집계된다(RLS).
  Future<Map<String, EventSummary>> fetchSummaries() async {
    final rows = await _client.from('event_payment_summaries').select();
    return {
      for (final r in rows) r['event_id'] as String: EventSummary.fromJson(r),
    };
  }

  // ---------------------------------------------------------------- 송금

  /// 본인 송금 현황: 이벤트 id → 송금 행. 행이 없으면 대상이 아니다.
  Future<Map<String, EventPayment>> fetchMyPayments(String userId) async {
    final rows = await _client
        .from('event_payments')
        .select('id, event_id, user_id, is_paid, paid_at, amount_override')
        .eq('user_id', userId);
    return {
      for (final r in rows) r['event_id'] as String: EventPayment.fromJson(r),
    };
  }

  Future<List<EventPayment>> fetchPayments(String eventId) async {
    final rows = await _client
        .from('event_payments')
        .select(_paymentColumns)
        .eq('event_id', eventId);
    final list = rows.map(EventPayment.fromJson).toList()
      ..sort(
        (a, b) =>
            (a.member?.studentId ?? '').compareTo(b.member?.studentId ?? ''),
      );
    return list;
  }

  /// 송금 여부 변경. 확인 시각/확인자는 DB 트리거가 기록한다.
  Future<void> setPaid(String paymentId, {required bool isPaid}) => _client
      .from('event_payments')
      .update({'is_paid': isPaid})
      .eq('id', paymentId)
      .expectAffected();

  /// 이 회원에게만 적용할 금액. null 이면 이벤트 기본 금액으로 되돌린다.
  Future<void> setAmountOverride(String paymentId, int? amount) => _client
      .from('event_payments')
      .update({'amount_override': amount})
      .eq('id', paymentId)
      .expectAffected();

  Future<void> addTargets(String eventId, Iterable<String> userIds) => _client
      .from('event_payments')
      .upsert(
        [
          for (final id in userIds) {'event_id': eventId, 'user_id': id},
        ],
        onConflict: 'event_id,user_id',
        ignoreDuplicates: true,
      );

  Future<void> removeTarget(String paymentId) => _client
      .from('event_payments')
      .delete()
      .eq('id', paymentId)
      .expectAffected();
}
