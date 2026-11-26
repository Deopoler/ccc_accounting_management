enum DepositStatus {
  unparsed('unparsed', '해석 실패'),
  unmatched('unmatched', '미매칭'),
  ambiguous('ambiguous', '후보 여럿'),
  autoMatched('auto_matched', '자동 확인'),
  manualMatched('manual_matched', '수동 연결'),
  ignored('ignored', '무시'),
  undone('undone', '취소됨');

  const DepositStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  bool get needsReview =>
      this == unparsed || this == unmatched || this == ambiguous;

  bool get canLink =>
      this == unmatched ||
      this == ambiguous ||
      this == undone ||
      this == ignored;

  bool get canUndo => this == autoMatched || this == manualMatched;

  bool get canIgnore =>
      this == unparsed ||
      this == unmatched ||
      this == ambiguous ||
      this == undone;

  bool get canRematch =>
      this == unmatched || this == ambiguous || this == undone;

  static DepositStatus parse(String value) => DepositStatus.values.firstWhere(
    (s) => s.dbValue == value,
    orElse: () => DepositStatus.unparsed,
  );
}

enum DepositFilter {
  needsReview('검토 필요', 'needs_review'),
  autoMatched('자동 확인', 'auto_matched'),
  manualMatched('수동 연결', 'manual_matched'),
  ignored('무시', 'ignored'),
  undone('취소됨', 'undone'),
  all('전체', 'all');

  const DepositFilter(this.label, this.dbGroup);

  final String label;
  final String dbGroup;

  bool matches(DepositStatus status) => switch (this) {
    DepositFilter.needsReview => status.needsReview,
    DepositFilter.autoMatched => status == DepositStatus.autoMatched,
    DepositFilter.manualMatched => status == DepositStatus.manualMatched,
    DepositFilter.ignored => status == DepositStatus.ignored,
    DepositFilter.undone => status == DepositStatus.undone,
    DepositFilter.all => true,
  };
}

class DepositCounts {
  const DepositCounts({
    this.needsReview = 0,
    this.autoMatched = 0,
    this.manualMatched = 0,
    this.ignored = 0,
    this.undone = 0,
    this.all = 0,
    this.unparsedWithRaw = 0,
  });

  factory DepositCounts.fromJson(Map<String, dynamic> json) => DepositCounts(
    needsReview: (json['needs_review'] as num? ?? 0).toInt(),
    autoMatched: (json['auto_matched'] as num? ?? 0).toInt(),
    manualMatched: (json['manual_matched'] as num? ?? 0).toInt(),
    ignored: (json['ignored'] as num? ?? 0).toInt(),
    undone: (json['undone'] as num? ?? 0).toInt(),
    all: (json['all_count'] as num? ?? 0).toInt(),
    unparsedWithRaw: (json['unparsed_with_raw'] as num? ?? 0).toInt(),
  );

  static const empty = DepositCounts();

  final int needsReview;
  final int autoMatched;
  final int manualMatched;
  final int ignored;
  final int undone;
  final int all;
  final int unparsedWithRaw;

  int countFor(DepositFilter filter) => switch (filter) {
    DepositFilter.needsReview => needsReview,
    DepositFilter.autoMatched => autoMatched,
    DepositFilter.manualMatched => manualMatched,
    DepositFilter.ignored => ignored,
    DepositFilter.undone => undone,
    DepositFilter.all => all,
  };
}

class DepositCandidate {
  const DepositCandidate({
    required this.kind,
    required this.userId,
    required this.label,
    required this.amount,
    this.eventId,
    this.eventPaymentId,
    this.orderIds = const [],
    this.matchMode = 'exact',
  });

  factory DepositCandidate.fromJson(Map<String, dynamic> json) {
    final rawIds = json['order_ids'];
    final orderIds = rawIds is List<dynamic>
        ? rawIds.whereType<String>().toList()
        : const <String>[];
    return DepositCandidate(
      kind: json['kind'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      amount: (json['amount'] as num? ?? 0).toInt(),
      eventId: json['event_id'] as String?,
      eventPaymentId: json['event_payment_id'] as String?,
      orderIds: orderIds,
      matchMode: json['match_mode'] as String? ?? 'exact',
    );
  }

  final String kind;
  final String userId;
  final String label;
  final int amount;
  final String? eventId;
  final String? eventPaymentId;
  final List<String> orderIds;
  final String matchMode;

  bool get isEvent => kind == 'event';

  bool get isLinkable =>
      (isEvent && eventPaymentId != null && eventPaymentId!.isNotEmpty) ||
      (!isEvent && orderIds.isNotEmpty);
}

class BankDeposit {
  const BankDeposit({
    required this.id,
    required this.campusId,
    required this.bankCode,
    required this.status,
    required this.depositedAt,
    required this.receivedAt,
    this.depositorName,
    this.amount,
    this.rawTitle,
    this.rawText,
    this.rawPackage,
    this.rawExpiresAt,
    this.matchReason,
    this.candidates = const [],
    this.matchedAt,
    this.matchedBy,
    this.undoneAt,
    this.undoneBy,
    this.ignoredAt,
    this.ignoredBy,
    this.duplicateCount = 0,
    this.lastDuplicateAt,
    this.duplicateOfId,
    this.duplicateClearedAt,
    this.duplicateClearedBy,
  });

  factory BankDeposit.fromJson(Map<String, dynamic> json) {
    final rawCandidates = json['candidate_snapshot'];
    final candidates = rawCandidates is List<dynamic>
        ? rawCandidates
              .whereType<Map<String, dynamic>>()
              .map(DepositCandidate.fromJson)
              .toList()
        : const <DepositCandidate>[];
    return BankDeposit(
      id: json['id'] as String,
      campusId: json['campus_id'] as String,
      bankCode: json['bank_code'] as String? ?? 'toss',
      status: DepositStatus.parse(json['status'] as String),
      depositorName: json['depositor_name'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      depositedAt: DateTime.parse(json['deposited_at'] as String),
      receivedAt: DateTime.parse(json['received_at'] as String),
      rawTitle: json['raw_title'] as String?,
      rawText: json['raw_text'] as String?,
      rawPackage: json['raw_package'] as String?,
      rawExpiresAt: _parseOptionalTime(json['raw_expires_at']),
      matchReason: json['match_reason'] as String?,
      candidates: candidates,
      matchedAt: _parseOptionalTime(json['matched_at']),
      matchedBy: json['matched_by'] as String?,
      undoneAt: _parseOptionalTime(json['undone_at']),
      undoneBy: json['undone_by'] as String?,
      ignoredAt: _parseOptionalTime(json['ignored_at']),
      ignoredBy: json['ignored_by'] as String?,
      duplicateCount: (json['duplicate_count'] as num? ?? 0).toInt(),
      lastDuplicateAt: _parseOptionalTime(json['last_duplicate_at']),
      duplicateOfId: json['duplicate_of_id'] as String?,
      duplicateClearedAt: _parseOptionalTime(json['duplicate_cleared_at']),
      duplicateClearedBy: json['duplicate_cleared_by'] as String?,
    );
  }

  final String id;
  final String campusId;
  final String bankCode;
  final DepositStatus status;
  final String? depositorName;
  final int? amount;
  final DateTime depositedAt;
  final DateTime receivedAt;
  final String? rawTitle;
  final String? rawText;
  final String? rawPackage;
  final DateTime? rawExpiresAt;
  final String? matchReason;
  final List<DepositCandidate> candidates;
  final DateTime? matchedAt;
  final String? matchedBy;
  final DateTime? undoneAt;
  final String? undoneBy;
  final DateTime? ignoredAt;
  final String? ignoredBy;
  final int duplicateCount;
  final DateTime? lastDuplicateAt;
  final String? duplicateOfId;
  final DateTime? duplicateClearedAt;
  final String? duplicateClearedBy;

  bool get isParsed => depositorName != null && amount != null;

  bool get isPossibleDuplicate =>
      duplicateOfId != null && duplicateClearedAt == null;

  bool get hasRawText =>
      (rawTitle != null && rawTitle!.isNotEmpty) ||
      (rawText != null && rawText!.isNotEmpty);

  String get reasonLabel => depositReasonLabel(matchReason, status: status);
}

class CampusDepositSettings {
  const CampusDepositSettings({
    required this.campusId,
    this.enabled = false,
    this.bankCode = 'toss',
    this.accountLabel = '',
    this.tokenPrefix,
    this.tokenRotatedAt,
    this.lastReceivedAt,
    this.lastDepositNotificationAt,
    this.lastIgnoredAt,
    this.lastIgnoredReason,
    this.ignoredCount = 0,
  });

  factory CampusDepositSettings.empty(String campusId) =>
      CampusDepositSettings(campusId: campusId);

  factory CampusDepositSettings.fromJson(Map<String, dynamic> json) =>
      CampusDepositSettings(
        campusId: json['campus_id'] as String,
        enabled: json['enabled'] as bool? ?? false,
        bankCode: json['bank_code'] as String? ?? 'toss',
        accountLabel: json['account_label'] as String? ?? '',
        tokenPrefix: json['token_prefix'] as String?,
        tokenRotatedAt: _parseOptionalTime(json['token_rotated_at']),
        lastReceivedAt: _parseOptionalTime(json['last_received_at']),
        lastDepositNotificationAt: _parseOptionalTime(
          json['last_deposit_notification_at'],
        ),
        lastIgnoredAt: _parseOptionalTime(json['last_ignored_at']),
        lastIgnoredReason: json['last_ignored_reason'] as String?,
        ignoredCount: (json['ignored_count'] as num? ?? 0).toInt(),
      );

  final String campusId;
  final bool enabled;
  final String bankCode;
  final String accountLabel;
  final String? tokenPrefix;
  final DateTime? tokenRotatedAt;
  final DateTime? lastReceivedAt;
  final DateTime? lastDepositNotificationAt;
  final DateTime? lastIgnoredAt;
  final String? lastIgnoredReason;
  final int ignoredCount;

  bool get hasToken => tokenPrefix != null && tokenPrefix!.isNotEmpty;

  String get lastIgnoredReasonLabel => ignoredReasonLabel(lastIgnoredReason);
}

class UnpaidEventTarget {
  const UnpaidEventTarget({
    required this.paymentId,
    required this.eventId,
    required this.eventTitle,
    required this.memberName,
    required this.studentId,
    required this.amount,
    required this.expectedDepositName,
  });

  final String paymentId;
  final String eventId;
  final String eventTitle;
  final String memberName;
  final String studentId;
  final int amount;
  final String expectedDepositName;
}

class UnpaidOrderTarget {
  const UnpaidOrderTarget({
    required this.orderId,
    required this.memberName,
    required this.studentId,
    required this.roundLabel,
    required this.itemsSummary,
    required this.amount,
    required this.createdAt,
  });

  final String orderId;
  final String memberName;
  final String studentId;
  final String roundLabel;
  final String itemsSummary;
  final int amount;
  final DateTime createdAt;
}

class UnpaidLinkTargets {
  const UnpaidLinkTargets({
    required this.orders,
    required this.eventPayments,
  });

  static const empty = UnpaidLinkTargets(orders: [], eventPayments: []);

  final List<UnpaidOrderTarget> orders;
  final List<UnpaidEventTarget> eventPayments;
}

String depositIngestUrl(String supabaseUrl) {
  final trimmed = supabaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return '';
  return '$trimmed/functions/v1/deposit-ingest';
}

String bankDisplayName(String bankCode) => switch (bankCode) {
  'toss' => '토스뱅크',
  _ => bankCode,
};

String depositReasonLabel(String? reason, {DepositStatus? status}) {
  return switch (reason) {
    'exact_event' => '이벤트 입금자명과 금액이 일치했습니다.',
    'prefix_event' => '잘린 이벤트 입금자명(앞부분)과 금액이 일치했습니다.',
    'exact_textbook_single' => '교재 신청 1건과 이름 · 금액이 일치했습니다.',
    'prefix_textbook_single' => '잘린 입금자명과 교재 신청 1건이 일치했습니다.',
    'exact_textbook_round_sum' => '같은 회차 교재 신청 합계와 일치했습니다.',
    'prefix_textbook_round_sum' => '잘린 입금자명과 같은 회차 교재 합계가 일치했습니다.',
    'no_candidate' => '일치하는 미납 교재 신청이나 이벤트가 없습니다.',
    'multiple_candidates' => '이름과 금액이 같은 미납 후보가 여러 건입니다.',
    'cross_type_conflict' => '교재 신청과 이벤트 모두 일치해 자동 확인하지 않았습니다.',
    'same_name_members' => '같은 이름의 회원이 여러 명 있어 확인이 필요합니다.',
    'possible_duplicate' => '60초 안에 같은 내용의 입금 알림이 있어 중복 여부를 확인해야 합니다.',
    'duplicate_cleared' => '관리자가 중복 아님으로 확인했습니다.',
    'match_error' => '자동 매칭 중 오류가 발생해 수동 확인이 필요합니다.',
    'empty_depositor_name' => '입금자명이 비어 있어 자동 확인하지 않았습니다.',
    'manual_link_event' => '관리자가 이벤트 송금과 연결했습니다.',
    'manual_link_orders' => '관리자가 교재 신청과 연결했습니다.',
    'no_amount' => '알림에서 입금 금액을 찾지 못했습니다.',
    'multiple_amounts' => '알림에 금액이 여러 개 있어 구분하지 못했습니다.',
    'invalid_amount' => '금액 형식이 올바르지 않습니다.',
    'no_depositor' => '알림에서 입금자명을 찾지 못했습니다.',
    'parse_failed' => '알림 형식을 해석하지 못했습니다.',
    'raw_expired' => '원문 보관 기간(14일)이 지나 내용이 삭제되었습니다.',
    'unsupported_bank' => '지원하지 않는 은행 형식입니다.',
    'no_account_label' ||
    'config_missing_label' ||
    'withdrawal' ||
    'outgoing_transfer' ||
    'ad' ||
    'empty' ||
    'ignored' => ignoredReasonLabel(reason),
    null || '' => switch (status) {
      DepositStatus.undone => '관리자가 입금 확인을 취소했습니다.',
      DepositStatus.ignored => '관리자가 무시 처리했습니다.',
      DepositStatus.unparsed => '알림 형식을 해석하지 못했습니다.',
      _ => '',
    },
    _ => reason,
  };
}

String ignoredReasonLabel(String? reason) => switch (reason) {
  'no_account_label' => '계좌 별칭 없음 (개인 계좌 등)',
  'config_missing_label' => '계좌 별칭 미설정',
  'withdrawal' => '출금 · 결제 알림',
  'outgoing_transfer' => '출금 이체',
  'ad' => '광고 · 혜택 알림',
  'empty' => '빈 알림',
  'ignored' => '무시됨',
  null || '' => '없음',
  _ => reason,
};

const _genericAccountLabels = {
  '토스',
  '토스뱅크',
  '모임',
  '모임통장',
  '통장',
  '입금',
  '계좌',
  '내계좌',
  '내통장',
  '회비',
  '회비통장',
  '동아리',
  '동아리통장',
  '은행',
  'toss',
  'tossbank',
  'bank',
  'account',
};

/// 서버 `validate_deposit_account_label` 과 동일한 계좌 별칭 검사.
String? validateDepositAccountLabel(String? value, {required bool enabled}) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return enabled ? '자동 입금 확인을 켜려면 계좌 별칭을 입력해 주세요.' : null;
  }
  final norm = trimmed.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (norm.length < 4) {
    return '계좌 별칭은 공백 제외 4자 이상 입력해 주세요.';
  }
  if (_genericAccountLabels.contains(norm)) {
    return '너무 일반적인 계좌 별칭은 사용할 수 없습니다. 캠퍼스 이름이 들어가게 입력해 주세요.';
  }
  return null;
}

DateTime? _parseOptionalTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
