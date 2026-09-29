import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/download/download.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/domain/profile.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/event_providers.dart';
import '../../events/presentation/widgets/event_widgets.dart';
import '../domain/csv_exports.dart';
import 'admin_events_page.dart';
import 'member_providers.dart';

enum _PaidFilter { all, unpaid, paid }

class AdminEventDetailPage extends ConsumerStatefulWidget {
  const AdminEventDetailPage({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<AdminEventDetailPage> createState() =>
      _AdminEventDetailPageState();
}

class _AdminEventDetailPageState extends ConsumerState<AdminEventDetailPage> {
  _PaidFilter _filter = _PaidFilter.all;
  final _search = TextEditingController();
  final Set<String> _busy = {};

  String get _id => widget.eventId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refreshLists() {
    ref
      ..invalidate(eventsProvider)
      ..invalidate(eventSummariesProvider)
      ..invalidate(eventProvider(_id))
      ..invalidate(eventPaymentsProvider(_id));
  }

  Future<void> _toggle(EventPayment p, bool isPaid) async {
    setState(() => _busy.add(p.id));
    try {
      await ref
          .read(eventPaymentsProvider(_id).notifier)
          .setPaid(p.id, isPaid: isPaid);
      ref.invalidate(eventSummariesProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _editAmount(Event event, EventPayment p) async {
    final result = await showDialog<_AmountResult>(
      context: context,
      builder: (_) => _AmountDialog(event: event, payment: p),
    );
    if (result == null || !mounted) return;
    setState(() => _busy.add(p.id));
    try {
      await ref
          .read(eventPaymentsProvider(_id).notifier)
          .setAmountOverride(p.id, result.amount);
      ref.invalidate(eventSummariesProvider);
      if (mounted) {
        showSnack(
          context,
          result.amount == null
              ? '기본 금액으로 되돌렸습니다.'
              : '${p.member?.name ?? '회원'}의 금액을 ${formatWon(result.amount!)}으로 바꿨습니다.',
        );
      }
    } catch (err) {
      if (mounted) showErrorSnack(context, err);
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _removeTarget(EventPayment p) async {
    final ok = await showConfirmDialog(
      context,
      title: '대상에서 제외',
      message: '${p.member?.name ?? '이 회원'}을(를) 이 이벤트의 송금 대상에서 제외하시겠습니까?',
      confirmLabel: '제외',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(eventRepositoryProvider).removeTarget(p.id);
      _refreshLists();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _addTargets(List<EventPayment> current) async {
    final existing = current.map((p) => p.userId).toSet();
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _AddTargetsDialog(excluded: existing),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    try {
      await ref.read(eventRepositoryProvider).addTargets(_id, selected);
      _refreshLists();
      if (mounted) showSnack(context, '${selected.length}명을 대상에 추가했습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _edit(Event event) async {
    final input = await showEventFormDialog(context, initial: event);
    if (input == null || !mounted) return;
    try {
      await ref.read(eventRepositoryProvider).updateEvent(event.id, input);
      _refreshLists();
      if (mounted) showSnack(context, '이벤트를 수정했습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(Event event) async {
    final ok = await showConfirmDialog(
      context,
      title: '이벤트 삭제',
      message: '"${event.title}"과(와) 모든 송금 기록을 삭제합니다. 되돌릴 수 없습니다.',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(eventRepositoryProvider).deleteEvent(event.id);
      ref
        ..invalidate(eventsProvider)
        ..invalidate(eventSummariesProvider);
      if (mounted) {
        showSnack(context, '이벤트를 삭제했습니다.');
        context.go(AppRoutes.adminEvents);
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _copyUnpaid(List<EventPayment> payments) async {
    final unpaid = payments.where((p) => !p.isPaid).toList();
    final text = unpaid
        .map((p) => '${p.member?.name ?? '-'}(${p.member?.studentId ?? '-'})')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSnack(context, '미납자 ${unpaid.length}명을 복사했습니다.');
  }

  void _exportUnpaid(Event event, List<EventPayment> payments) {
    try {
      downloadTextFile(
        safeFileName('미납자_${event.title}_${todayStamp()}.csv'),
        encodeCsv(unpaidCsvRows(event, payments)),
      );
    } catch (e) {
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(eventProvider(_id));
    final payments = ref.watch(eventPaymentsProvider(_id));

    if (event.hasError || payments.hasError) {
      return ErrorView(
        error: (event.error ?? payments.error)!,
        onRetry: _refreshLists,
      );
    }
    if (!event.hasValue || !payments.hasValue) return const LoadingView();

    final e = event.requireValue;
    if (e == null) {
      return const EmptyView(message: '이벤트를 찾을 수 없습니다.');
    }
    final all = payments.requireValue;
    final summary = EventSummary.fromPayments(all, e);
    final q = _search.text.trim().toLowerCase();
    final visible = all.where((p) {
      if (_filter == _PaidFilter.paid && !p.isPaid) return false;
      if (_filter == _PaidFilter.unpaid && p.isPaid) return false;
      if (q.isEmpty) return true;
      final m = p.member;
      return m != null &&
          (m.name.toLowerCase().contains(q) ||
              m.studentId.toLowerCase().contains(q));
    }).toList();

    final theme = Theme.of(context);
    return ScrollPageBody(
      maxWidth: 900,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '수정',
                      onPressed: () => _edit(e),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '삭제',
                      onPressed: () => _delete(e),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                EventMetaLine(event: e),
                const SizedBox(height: 4),
                Text(
                  e.depositName.isEmpty
                      ? '입금자명: 회원 이름'
                      : '입금자명 형식: ${e.depositName}',
                  style: theme.textTheme.bodySmall,
                ),
                if (e.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(e.description),
                ],
                const SizedBox(height: 16),
                PaymentProgress(summary: summary),
                const SizedBox(height: 12),
                LabeledValue(
                  label: '미납 ${summary.unpaidCount}명 · 미수금',
                  value: AmountText(
                    summary.outstandingAmount,
                    highlight: summary.unpaidCount > 0,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (f, label) in [
              (_PaidFilter.all, '전체 ${summary.targetCount}'),
              (_PaidFilter.unpaid, '미납 ${summary.unpaidCount}'),
              (_PaidFilter.paid, '완납 ${summary.paidCount}'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '학번 / 이름 검색',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _addTargets(all),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('대상 추가'),
            ),
            OutlinedButton.icon(
              onPressed: summary.unpaidCount == 0
                  ? null
                  : () => _copyUnpaid(all),
              icon: const Icon(Icons.copy),
              label: const Text('미납자 복사'),
            ),
            OutlinedButton.icon(
              onPressed: summary.unpaidCount == 0
                  ? null
                  : () => _exportUnpaid(e, all),
              icon: const Icon(Icons.download),
              label: const Text('미납자 CSV'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (all.isEmpty)
          EmptyView(
            icon: Icons.group_add_outlined,
            message: '아직 송금 대상이 없습니다.\n대상 추가에서 회원을 선택해 주세요.',
            action: FilledButton.icon(
              onPressed: () => _addTargets(all),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('대상 추가'),
            ),
          )
        else if (visible.isEmpty)
          const EmptyView(message: '해당하는 회원이 없습니다.')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, p) in visible.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(p.member?.name ?? '-'),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${p.member?.studentId ?? '-'} · '),
                          TextSpan(
                            text: p.hasCustomAmount
                                ? '${formatWon(p.amountFor(e))} (조정됨)'
                                : formatWon(p.amountFor(e)),
                            style: p.hasCustomAmount
                                ? TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  )
                                : null,
                          ),
                          if (e.depositName.isNotEmpty && p.member != null)
                            TextSpan(
                              text:
                                  ' · 입금자명 ${e.depositNameFor(name: p.member!.name, studentId: p.member!.studentId)}',
                            ),
                          if (p.paidAt != null)
                            TextSpan(
                              text: ' · 확인 ${formatDateTime(p.paidAt!)}',
                            ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PaymentBadge(payment: p),
                        const SizedBox(width: 4),
                        Switch(
                          value: p.isPaid,
                          onChanged: _busy.contains(p.id)
                              ? null
                              : (v) => _toggle(p, v),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '더보기',
                          enabled: !_busy.contains(p.id),
                          onSelected: (v) => v == 'amount'
                              ? _editAmount(e, p)
                              : _removeTarget(p),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'amount',
                              child: Text('금액 변경'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('대상에서 제외'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 송금 대상에 추가할 회원 선택.
class _AddTargetsDialog extends ConsumerStatefulWidget {
  const _AddTargetsDialog({required this.excluded});

  final Set<String> excluded;

  @override
  ConsumerState<_AddTargetsDialog> createState() => _AddTargetsDialogState();
}

class _AddTargetsDialogState extends ConsumerState<_AddTargetsDialog> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    return AlertDialog(
      title: const Text('송금 대상 추가'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: AsyncValueView<List<Profile>>(
          value: members,
          onRetry: () => ref.invalidate(membersProvider),
          data: (list) {
            final q = _query.trim().toLowerCase();
            final candidates = list
                .where((m) => m.isApproved && !widget.excluded.contains(m.id))
                .where(
                  (m) =>
                      q.isEmpty ||
                      m.name.toLowerCase().contains(q) ||
                      m.studentId.toLowerCase().contains(q),
                )
                .toList();
            final ids = candidates.map((m) => m.id).toSet();
            final selectedCount = ids.where(_selected.contains).length;
            final allSelected = ids.isNotEmpty && selectedCount == ids.length;
            return Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: '학번 / 이름 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                if (candidates.isNotEmpty) ...[
                  CheckboxListTile(
                    tristate: true,
                    value: allSelected
                        ? true
                        : (selectedCount == 0 ? false : null),
                    onChanged: (_) => setState(
                      () => allSelected
                          ? _selected.removeAll(ids)
                          : _selected.addAll(ids),
                    ),
                    title: Text(
                      q.isEmpty
                          ? '회원 전체 선택 (${ids.length}명)'
                          : '검색 결과 전체 선택 (${ids.length}명)',
                    ),
                  ),
                  const Divider(height: 1),
                ],
                Expanded(
                  child: candidates.isEmpty
                      ? const EmptyView(message: '추가할 수 있는 회원이 없습니다.')
                      : ListView(
                          children: [
                            for (final m in candidates)
                              CheckboxListTile(
                                value: _selected.contains(m.id),
                                onChanged: (v) => setState(
                                  () => v == true
                                      ? _selected.add(m.id)
                                      : _selected.remove(m.id),
                                ),
                                title: Text(m.name),
                                subtitle: Text(
                                  '${m.studentId} · ${m.role.label}',
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text('${_selected.length}명 추가'),
        ),
      ],
    );
  }
}

/// 금액 변경 결과. [amount] 가 null 이면 기본 금액으로 되돌린다.
class _AmountResult {
  const _AmountResult(this.amount);

  final int? amount;
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.event, required this.payment});

  final Event event;
  final EventPayment payment;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.payment.amountFor(widget.event).toString(),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final value = int.parse(_amount.text);
    // 기본 금액과 같으면 조정하지 않은 것으로 저장한다.
    Navigator.pop(
      context,
      _AmountResult(value == widget.event.amount ? null : value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.payment.member;
    return AlertDialog(
      title: const Text('금액 변경'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${m?.name ?? '-'}(${m?.studentId ?? '-'})에게만 적용됩니다. '
                '기본 금액: ${formatWon(widget.event.amount)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '금액',
                  suffixText: '원',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null) return '금액을 입력해 주세요.';
                  if (n > 100000000) return '금액이 너무 큽니다.';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.payment.hasCustomAmount)
          TextButton(
            onPressed: () => Navigator.pop(context, const _AmountResult(null)),
            child: const Text('기본 금액으로'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}
