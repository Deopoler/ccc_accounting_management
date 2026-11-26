import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/korean_search.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../admin/presentation/admin_order_providers.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../events/presentation/event_providers.dart';
import '../domain/bank_deposit.dart';
import 'deposit_providers.dart';

class AdminDepositsPage extends ConsumerStatefulWidget {
  const AdminDepositsPage({super.key});

  @override
  ConsumerState<AdminDepositsPage> createState() => _AdminDepositsPageState();
}

class _AdminDepositsPageState extends ConsumerState<AdminDepositsPage> {
  DepositFilter _filter = DepositFilter.needsReview;
  final _search = TextEditingController();
  final Set<String> _busy = {};
  bool _bulkReparsing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref
      ..invalidate(bankDepositsProvider)
      ..invalidate(unpaidLinkTargetsProvider)
      ..invalidate(adminOrdersProvider)
      ..invalidate(eventPaymentsProvider)
      ..invalidate(eventSummariesProvider);
  }

  Future<void> _runFor(
    String depositId,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy.contains(depositId)) return;
    setState(() => _busy.add(depositId));
    try {
      await action();
      _refreshAll();
      if (mounted && successMessage != null) {
        showSnack(context, successMessage);
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(depositId));
    }
  }

  Future<void> _undo(BankDeposit deposit) async {
    final who = deposit.depositorName ?? '이 입금';
    final amountText = deposit.amount == null ? '' : ' (${formatWon(deposit.amount!)})';
    final ok = await showConfirmDialog(
      context,
      title: '입금 확인 취소',
      message:
          '$who$amountText의 입금 확인을 취소할까요?\n'
          '연결된 교재 신청이나 이벤트 송금이 미납 상태로 돌아갑니다.',
      confirmLabel: '확인 취소',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _runFor(
      deposit.id,
      () => ref.read(depositRepositoryProvider).undoDeposit(deposit.id),
      successMessage: '입금 확인을 취소했습니다.',
    );
  }

  Future<void> _ignore(BankDeposit deposit, {required bool ignore}) async {
    await _runFor(
      deposit.id,
      () => ref
          .read(depositRepositoryProvider)
          .ignoreDeposit(deposit.id, ignore: ignore),
      successMessage: ignore ? '입금을 무시 처리했습니다.' : '무시를 해제했습니다.',
    );
  }

  Future<void> _rematch(BankDeposit deposit) async {
    if (_busy.contains(deposit.id)) return;
    setState(() => _busy.add(deposit.id));
    try {
      final status = await ref
          .read(depositRepositoryProvider)
          .rematchDeposit(deposit.id);
      _refreshAll();
      if (!mounted) return;
      final message = switch (status) {
        DepositStatus.autoMatched => '자동 확인되었습니다.',
        DepositStatus.ambiguous => '일치하는 후보가 여러 건입니다. 직접 연결해 주세요.',
        _ => '일치하는 미납 대상을 찾지 못했습니다.',
      };
      showSnack(context, message);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(deposit.id));
    }
  }

  Future<void> _reparseOne(BankDeposit deposit) async {
    if (_busy.contains(deposit.id)) return;
    setState(() => _busy.add(deposit.id));
    try {
      final results = await ref
          .read(depositRepositoryProvider)
          .reparse(depositId: deposit.id);
      _refreshAll();
      if (!mounted) return;
      final next = results.isEmpty ? null : results.first.status;
      final message = switch (next) {
        DepositStatus.autoMatched => '다시 해석해 자동 확인했습니다.',
        DepositStatus.unmatched || DepositStatus.ambiguous =>
          '해석에 성공했습니다. 검토 목록에서 대상을 연결해 주세요.',
        DepositStatus.ignored => '입금 알림이 아니어서 무시 처리했습니다.',
        _ => '여전히 해석하지 못했습니다. 파서 수정 후 다시 시도해 주세요.',
      };
      showSnack(context, message);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(deposit.id));
    }
  }

  Future<void> _reparseAllUnparsed() async {
    if (_bulkReparsing) return;
    setState(() => _bulkReparsing = true);
    try {
      final campusId = await ref.requireAdminCampusId();
      final results = await ref
          .read(depositRepositoryProvider)
          .reparse(campusId: campusId);
      _refreshAll();
      if (!mounted) return;
      final matched = results
          .where((r) => r.status == DepositStatus.autoMatched)
          .length;
      final stillFailed = results
          .where((r) => r.status == DepositStatus.unparsed)
          .length;
      showSnack(
        context,
        '${results.length}건 재실행: 자동 확인 $matched건, 해석 실패 $stillFailed건',
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _bulkReparsing = false);
    }
  }

  Future<void> _openLinkDialog(BankDeposit deposit) async {
    final result = await showDialog<_LinkSelection>(
      context: context,
      builder: (_) => _LinkDepositDialog(deposit: deposit),
    );
    if (result == null || !mounted) return;
    await _runFor(
      deposit.id,
      () => switch (result) {
        _EventLinkSelection(:final eventPaymentId) => ref
            .read(depositRepositoryProvider)
            .linkToEvent(deposit.id, eventPaymentId),
        _OrdersLinkSelection(:final orderIds) => ref
            .read(depositRepositoryProvider)
            .linkToOrders(deposit.id, orderIds),
      },
      successMessage: '입금 대상을 연결했습니다.',
    );
  }

  bool _matchesSearch(BankDeposit d, String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    final amountStr = d.amount == null ? '' : '${d.amount} ${formatWon(d.amount!)}';
    final haystack = [
      d.depositorName ?? '',
      amountStr,
      d.rawTitle ?? '',
      d.rawText ?? '',
      d.reasonLabel,
    ].join(' ');
    return matchesKoreanQuery(haystack, q);
  }

  @override
  Widget build(BuildContext context) {
    final depositsAsync = ref.watch(bankDepositsProvider);

    return AsyncValueView<List<BankDeposit>>(
      value: depositsAsync,
      onRetry: () => ref.invalidate(bankDepositsProvider),
      data: (all) {
        final counts = {
          for (final f in DepositFilter.values)
            f: all.where((d) => f.matches(d.status)).length,
        };
        final unparsedWithRawCount = all
            .where((d) => d.status == DepositStatus.unparsed && d.hasRawText)
            .length;
        final visible = all
            .where(
              (d) =>
                  _filter.matches(d.status) && _matchesSearch(d, _search.text),
            )
            .toList();

        return ListView(
          children: [
            PageBody(
              maxWidth: 960,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in DepositFilter.values)
                        ChoiceChip(
                          label: Text('${f.label} ${counts[f] ?? 0}'),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 600;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: compact ? constraints.maxWidth : 280,
                            child: TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: '입금자명 / 금액 / 원문 검색',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: '지우기',
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _search.clear();
                                          setState(() {});
                                        },
                                      ),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _refreshAll,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('새로고침'),
                          ),
                          if (unparsedWithRawCount > 0)
                            OutlinedButton.icon(
                              onPressed: _bulkReparsing
                                  ? null
                                  : _reparseAllUnparsed,
                              icon: const Icon(Icons.replay, size: 18),
                              label: Text(
                                _bulkReparsing
                                    ? '재해석 중...'
                                    : '해석 실패 일괄 재실행 ($unparsedWithRawCount)',
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (all.isEmpty)
                    EmptyView(
                      icon: Icons.account_balance_wallet_outlined,
                      message:
                          '수집된 입금 내역이 아직 없습니다.\n'
                          '설정에서 자동 입금 확인을 켜고 알림 전달을 연결해 주세요.',
                      action: OutlinedButton(
                        onPressed: () => context.go(AppRoutes.adminSettings),
                        child: const Text('설정으로 이동'),
                      ),
                    )
                  else if (visible.isEmpty)
                    EmptyView(
                      icon: Icons.check_circle_outline,
                      message: _filter == DepositFilter.needsReview &&
                              _search.text.trim().isEmpty
                          ? '확인이 필요한 입금이 없습니다.'
                          : '조건에 맞는 입금 내역이 없습니다.',
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionTitle('입금 ${visible.length}건'),
                        for (final d in visible) ...[
                          _DepositCard(
                            deposit: d,
                            busy: _busy.contains(d.id),
                            onLink: () => _openLinkDialog(d),
                            onUndo: () => _undo(d),
                            onIgnore: () => _ignore(d, ignore: true),
                            onUnignore: () => _ignore(d, ignore: false),
                            onRematch: () => _rematch(d),
                            onReparse: () => _reparseOne(d),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DepositCard extends StatelessWidget {
  const _DepositCard({
    required this.deposit,
    required this.busy,
    required this.onLink,
    required this.onUndo,
    required this.onIgnore,
    required this.onUnignore,
    required this.onRematch,
    required this.onReparse,
  });

  final BankDeposit deposit;
  final bool busy;
  final VoidCallback onLink;
  final VoidCallback onUndo;
  final VoidCallback onIgnore;
  final VoidCallback onUnignore;
  final VoidCallback onRematch;
  final VoidCallback onReparse;

  BadgeTone _tone(DepositStatus s) => switch (s) {
    DepositStatus.unparsed ||
    DepositStatus.unmatched ||
    DepositStatus.ambiguous => BadgeTone.accent,
    DepositStatus.autoMatched ||
    DepositStatus.manualMatched => BadgeTone.neutral,
    DepositStatus.ignored || DepositStatus.undone => BadgeTone.muted,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final d = deposit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            d.depositorName ?? '입금자 미확인',
                            style: theme.textTheme.titleMedium,
                          ),
                          AppBadge(d.status.label, tone: _tone(d.status)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatDateTime(d.depositedAt)} · ${bankDisplayName(d.bankCode)}'
                        '${d.duplicateCount > 0 ? ' · 중복 재전송 ${d.duplicateCount}회' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (d.amount != null)
                  AmountText(
                    d.amount!,
                    size: AmountSize.small,
                    highlight: d.status.needsReview,
                  )
                else
                  Text(
                    '금액 미확인',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
              ],
            ),
            if (d.reasonLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                d.reasonLabel,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ],
            if (d.status == DepositStatus.unparsed) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: c.divider),
                ),
                child: d.hasRawText
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '원본 알림${d.rawPackage != null && d.rawPackage!.isNotEmpty ? ' (${d.rawPackage})' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (d.rawTitle != null && d.rawTitle!.isNotEmpty)
                            SelectableText(
                              '제목: ${d.rawTitle}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          if (d.rawText != null && d.rawText!.isNotEmpty)
                            SelectableText(
                              '내용: ${d.rawText}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          if (d.rawExpiresAt != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '원문 자동 삭제 예정: ${formatDate(d.rawExpiresAt!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Text(
                        '원문 보관 기간(14일)이 지나 내용이 삭제되었습니다.',
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
              ),
            ],
            if (d.candidates.isNotEmpty && d.status == DepositStatus.ambiguous) ...[
              const SizedBox(height: 8),
              Text(
                '후보: ${d.candidates.take(3).map((x) => '${x.label} (${formatWon(x.amount)})').join(', ')}'
                '${d.candidates.length > 3 ? ' 외 ${d.candidates.length - 3}건' : ''}',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (d.status == DepositStatus.unparsed && d.hasRawText)
                  OutlinedButton(
                    onPressed: busy ? null : onReparse,
                    child: const Text('다시 해석'),
                  ),
                if (d.isParsed && d.status.canLink)
                  OutlinedButton(
                    onPressed: busy ? null : onLink,
                    child: const Text('대상 연결'),
                  ),
                if (d.isParsed && d.status.canRematch)
                  OutlinedButton(
                    onPressed: busy ? null : onRematch,
                    child: const Text('다시 매칭'),
                  ),
                if (d.status.canUndo)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: c.error),
                    onPressed: busy ? null : onUndo,
                    child: const Text('확인 취소'),
                  ),
                if (d.status.canIgnore)
                  TextButton(
                    onPressed: busy ? null : onIgnore,
                    child: const Text('무시'),
                  ),
                if (d.status == DepositStatus.ignored && d.isParsed)
                  TextButton(
                    onPressed: busy ? null : onUnignore,
                    child: const Text('무시 해제'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

sealed class _LinkSelection {
  const _LinkSelection();
}

class _EventLinkSelection extends _LinkSelection {
  const _EventLinkSelection(this.eventPaymentId);

  final String eventPaymentId;
}

class _OrdersLinkSelection extends _LinkSelection {
  const _OrdersLinkSelection(this.orderIds);

  final List<String> orderIds;
}

enum _LinkTab { orders, events }

class _LinkDepositDialog extends ConsumerStatefulWidget {
  const _LinkDepositDialog({required this.deposit});

  final BankDeposit deposit;

  @override
  ConsumerState<_LinkDepositDialog> createState() => _LinkDepositDialogState();
}

class _LinkDepositDialogState extends ConsumerState<_LinkDepositDialog> {
  _LinkTab _tab = _LinkTab.orders;
  String _query = '';
  final Set<String> _selectedOrderIds = {};
  String? _selectedEventPaymentId;

  @override
  void initState() {
    super.initState();
    if (widget.deposit.candidates.isNotEmpty &&
        widget.deposit.candidates.every((c) => c.isEvent)) {
      _tab = _LinkTab.events;
    }
  }

  void _pickCandidate(DepositCandidate cand) {
    if (!cand.isLinkable) return;
    if (cand.isEvent) {
      Navigator.pop(context, _EventLinkSelection(cand.eventPaymentId!));
    } else {
      Navigator.pop(context, _OrdersLinkSelection(cand.orderIds));
    }
  }

  void _submitManual() {
    if (_tab == _LinkTab.events) {
      final id = _selectedEventPaymentId;
      if (id == null) return;
      Navigator.pop(context, _EventLinkSelection(id));
    } else {
      if (_selectedOrderIds.isEmpty) return;
      Navigator.pop(context, _OrdersLinkSelection(_selectedOrderIds.toList()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final targetsAsync = ref.watch(unpaidLinkTargetsProvider);
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final d = widget.deposit;
    final linkableCandidates = d.candidates.where((x) => x.isLinkable).toList();
    final canSubmit = _tab == _LinkTab.events
        ? _selectedEventPaymentId != null
        : _selectedOrderIds.isNotEmpty;

    return AlertDialog(
      title: const Text('입금 대상 연결'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: (availableHeight * 0.65).clamp(200.0, 520.0),
        ),
        child: SizedBox(
          width: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${d.depositorName ?? '-'} · ${d.amount == null ? '-' : formatWon(d.amount!)}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (linkableCandidates.isNotEmpty) ...[
                Text(
                  '추천 후보',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                for (final cand in linkableCandidates.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cand.label,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                Text(
                                  formatWon(cand.amount),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _pickCandidate(cand),
                            child: const Text('연결'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 16),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('미납 교재 신청'),
                    selected: _tab == _LinkTab.orders,
                    onSelected: (_) => setState(() => _tab = _LinkTab.orders),
                  ),
                  ChoiceChip(
                    label: const Text('미납 이벤트'),
                    selected: _tab == _LinkTab.events,
                    onSelected: (_) => setState(() => _tab = _LinkTab.events),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: '이름 / 학번 / 제목 검색',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AsyncValueView<UnpaidLinkTargets>(
                  value: targetsAsync,
                  onRetry: () => ref.invalidate(unpaidLinkTargetsProvider),
                  data: (targets) {
                    if (_tab == _LinkTab.orders) {
                      final filtered = targets.orders.where((o) {
                        final text =
                            '${o.memberName} ${o.studentId} ${o.itemsSummary} ${o.amount}';
                        return matchesKoreanQuery(text, _query);
                      }).toList();
                      if (filtered.isEmpty) {
                        return const EmptyView(message: '연결할 미납 교재 신청이 없습니다.');
                      }
                      final selectedSum = targets.orders
                          .where((o) => _selectedOrderIds.contains(o.orderId))
                          .fold<int>(0, (sum, o) => sum + o.amount);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_selectedOrderIds.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '선택 합계 ${formatWon(selectedSum)} (${_selectedOrderIds.length}건)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: c.primary,
                                ),
                              ),
                            ),
                          Expanded(
                            child: ListView(
                              children: [
                                for (final o in filtered)
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: _selectedOrderIds.contains(
                                      o.orderId,
                                    ),
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selectedOrderIds.add(o.orderId);
                                      } else {
                                        _selectedOrderIds.remove(o.orderId);
                                      }
                                    }),
                                    title: Text(
                                      '${o.memberName} (${o.studentId}) · ${formatWon(o.amount)}',
                                    ),
                                    subtitle: Text(
                                      '${o.roundLabel} 회차 · ${o.itemsSummary}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    final filtered = targets.eventPayments.where((p) {
                      final text =
                          '${p.memberName} ${p.studentId} ${p.eventTitle} ${p.expectedDepositName} ${p.amount}';
                      return matchesKoreanQuery(text, _query);
                    }).toList();
                    if (filtered.isEmpty) {
                      return const EmptyView(message: '연결할 미납 이벤트가 없습니다.');
                    }
                    return ListView(
                      children: [
                        for (final p in filtered)
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            selected: _selectedEventPaymentId == p.paymentId,
                            leading: Icon(
                              _selectedEventPaymentId == p.paymentId
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: _selectedEventPaymentId == p.paymentId
                                  ? c.primary
                                  : c.textSecondary,
                            ),
                            title: Text(
                              '${p.memberName} (${p.studentId}) · ${formatWon(p.amount)}',
                            ),
                            subtitle: Text(
                              '${p.eventTitle} · 입금자명 ${p.expectedDepositName}',
                            ),
                            onTap: () => setState(
                              () => _selectedEventPaymentId = p.paymentId,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submitManual : null,
          child: const Text('연결'),
        ),
      ],
    );
  }
}
