import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_exception.dart';
import '../../events/domain/event.dart';
import '../../textbooks/domain/textbook_order.dart';
import '../domain/bank_deposit.dart';

// token_hash and rate_window columns are not granted to authenticated.
const _settingsColumns =
    'campus_id, enabled, bank_code, account_label, token_prefix, token_rotated_at, '
    'last_received_at, last_deposit_notification_at, '
    'last_ignored_at, last_ignored_reason, ignored_count';

const _unpaidOrderColumns =
    'id, user_id, round_id, status, total_price, created_at, '
    'order_rounds(id, starts_at, deadline), '
    'profiles:profiles!textbook_orders_user_id_fkey(student_id, name), '
    'textbook_order_items(textbook_id, quantity, unit_price, textbooks(title))';

const _unpaidEventPaymentColumns =
    'id, event_id, user_id, amount_override, '
    'events!inner(id, campus_id, title, amount, deposit_name), '
    'member:profiles!event_payments_user_id_fkey(student_id, name)';

class DepositRepository {
  DepositRepository(this._client);

  final SupabaseClient _client;

  Future<CampusDepositSettings> fetchSettings(String campusId) async {
    final row = await _client
        .from('campus_deposit_settings')
        .select(_settingsColumns)
        .eq('campus_id', campusId)
        .maybeSingle();
    if (row == null) return CampusDepositSettings.empty(campusId);
    return CampusDepositSettings.fromJson(row);
  }

  Future<void> updateSettings(
    String campusId, {
    required bool enabled,
    required String bankCode,
    required String accountLabel,
  }) => _client.rpc<void>(
    'admin_update_deposit_settings',
    params: {
      'p_campus_id': campusId,
      'p_enabled': enabled,
      'p_bank_code': bankCode,
      'p_account_label': accountLabel.trim(),
    },
  );

  Future<String> rotateToken(String campusId) => _client.rpc<String>(
    'admin_rotate_deposit_token',
    params: {'p_campus_id': campusId},
  );

  Future<List<BankDeposit>> fetchDeposits(
    String campusId, {
    DepositFilter filter = DepositFilter.all,
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'admin_list_bank_deposits',
      params: {
        'p_campus_id': campusId,
        'p_status_group': filter.dbGroup,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return rows
        .whereType<Map<String, dynamic>>()
        .map(BankDeposit.fromJson)
        .toList();
  }

  Future<DepositCounts> fetchDepositCounts(String campusId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'admin_count_bank_deposits',
      params: {'p_campus_id': campusId},
    );
    final list = rows.whereType<Map<String, dynamic>>().toList();
    if (list.isEmpty) return DepositCounts.empty;
    return DepositCounts.fromJson(list.first);
  }

  Future<UnpaidLinkTargets> fetchUnpaidLinkTargets(String campusId) async {
    final orderRows = await _client
        .from('textbook_orders')
        .select(_unpaidOrderColumns)
        .eq('campus_id', campusId)
        .eq('status', 'requested')
        .order('created_at', ascending: false);

    final orders = <UnpaidOrderTarget>[];
    for (final row in orderRows) {
      final order = TextbookOrder.fromJson(row);
      final items = order.items
          .map((i) => '${i.title} ×${i.quantity}')
          .join(', ');
      orders.add(
        UnpaidOrderTarget(
          orderId: order.id,
          memberName: order.member?.name ?? '-',
          studentId: order.member?.studentId ?? '',
          roundLabel: order.round?.label ?? '-',
          itemsSummary: items.isEmpty ? '교재 신청' : items,
          amount: order.totalPrice,
          createdAt: order.createdAt,
        ),
      );
    }

    final paymentRows = await _client
        .from('event_payments')
        .select(_unpaidEventPaymentColumns)
        .eq('is_paid', false)
        .eq('events.campus_id', campusId);

    final payments = <UnpaidEventTarget>[];
    for (final row in paymentRows) {
      final ev = row['events'] as Map<String, dynamic>?;
      final member = row['member'] as Map<String, dynamic>?;
      if (ev == null) continue;
      final name = member?['name'] as String? ?? '-';
      final studentId = member?['student_id'] as String? ?? '';
      final override = (row['amount_override'] as num?)?.toInt();
      final baseAmount = (ev['amount'] as num? ?? 0).toInt();
      final template = ev['deposit_name'] as String? ?? '';
      payments.add(
        UnpaidEventTarget(
          paymentId: row['id'] as String,
          eventId: ev['id'] as String,
          eventTitle: ev['title'] as String? ?? '',
          memberName: name,
          studentId: studentId,
          amount: override ?? baseAmount,
          expectedDepositName: renderDepositName(
            template,
            name: name,
            studentId: studentId,
          ),
        ),
      );
    }
    payments.sort((a, b) {
      final byEvent = a.eventTitle.compareTo(b.eventTitle);
      if (byEvent != 0) return byEvent;
      return a.memberName.compareTo(b.memberName);
    });

    return UnpaidLinkTargets(orders: orders, eventPayments: payments);
  }

  Future<void> linkToEvent(
    String depositId,
    String eventPaymentId, {
    bool allowAmountMismatch = false,
  }) => _client.rpc<void>(
    'admin_link_deposit_to_event',
    params: {
      'p_deposit_id': depositId,
      'p_event_payment_id': eventPaymentId,
      'p_allow_amount_mismatch': allowAmountMismatch,
    },
  );

  Future<void> linkToOrders(
    String depositId,
    List<String> orderIds, {
    bool allowAmountMismatch = false,
  }) => _client.rpc<void>(
    'admin_link_deposit_to_orders',
    params: {
      'p_deposit_id': depositId,
      'p_order_ids': orderIds,
      'p_allow_amount_mismatch': allowAmountMismatch,
    },
  );

  Future<void> undoDeposit(String depositId) => _client.rpc<void>(
    'admin_undo_deposit',
    params: {'p_deposit_id': depositId},
  );

  Future<void> clearPossibleDuplicate(String depositId) => _client.rpc<void>(
    'admin_clear_possible_duplicate',
    params: {'p_deposit_id': depositId},
  );

  Future<void> ignoreDeposit(String depositId, {required bool ignore}) =>
      _client.rpc<void>(
        'admin_ignore_deposit',
        params: {'p_deposit_id': depositId, 'p_ignore': ignore},
      );

  Future<DepositStatus> rematchDeposit(String depositId) async {
    final raw = await _client.rpc<String>(
      'admin_rematch_deposit',
      params: {'p_deposit_id': depositId},
    );
    return DepositStatus.parse(raw);
  }

  Future<List<({String depositId, DepositStatus status})>> reparse({
    String? depositId,
    String? campusId,
  }) async {
    final res = await _client.functions.invoke(
      'deposit-reparse',
      body: {
        'deposit_id': ?depositId,
        'campus_id': ?campusId,
      },
    );
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final results = data['results'];
      if (results is List<dynamic>) {
        return [
          for (final item in results.whereType<Map<String, dynamic>>())
            (
              depositId: item['deposit_id'] as String? ?? '',
              status: DepositStatus.parse(item['status'] as String? ?? ''),
            ),
        ];
      }
      final err = data['error'];
      if (err is String) {
        throw AppException(err);
      }
    }
    return const [];
  }
}
