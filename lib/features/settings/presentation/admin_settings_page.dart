import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../textbooks/domain/order_round.dart';
import '../../textbooks/presentation/textbook_providers.dart';
import '../domain/bank_account.dart';
import 'settings_providers.dart';

class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(bankAccountProvider(CampusScope.admin));
    return AsyncValueView(
      value: account,
      onRetry: () => ref.invalidate(bankAccountProvider),
      data: (a) => ScrollPageBody(
        maxWidth: 640,
        children: [
          _BankAccountForm(initial: a),
          const SizedBox(height: 24),
          const _RoundDeadlineForm(),
          const SizedBox(height: 16),
          const _DefaultPasswordInfo(),
        ],
      ),
    );
  }
}

class _BankAccountForm extends ConsumerStatefulWidget {
  const _BankAccountForm({required this.initial});

  final BankAccount initial;

  @override
  ConsumerState<_BankAccountForm> createState() => _BankAccountFormState();
}

class _BankAccountFormState extends ConsumerState<_BankAccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final _bank = TextEditingController(text: widget.initial.bankName);
  late final _number = TextEditingController(
    text: widget.initial.accountNumber,
  );
  late final _holder = TextEditingController(text: widget.initial.holder);
  bool _saving = false;

  @override
  void dispose() {
    _bank.dispose();
    _number.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveBankAccount(
            await ref.requireAdminCampusId(),
            BankAccount(
              bankName: _bank.text,
              accountNumber: _number.text,
              holder: _holder.text,
            ),
          );
      ref.invalidate(bankAccountProvider);
      if (mounted) showSnack(context, '송금 계좌를 저장했습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v, String label) =>
        (v == null || v.trim().isEmpty) ? '$label을(를) 입력해 주세요.' : null;

    // 입력칸이 회색 면이라 카드 없이 흰 배경에 둔다.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('송금 계좌'),
            Text(
              '교재 신청 완료 화면과 이벤트 화면에서 회원에게 안내됩니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bank,
              decoration: const InputDecoration(labelText: '은행'),
              validator: (v) => required(v, '은행'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _number,
              decoration: const InputDecoration(
                labelText: '계좌번호',
                hintText: '예) 123-456-789012',
              ),
              validator: (v) => required(v, '계좌번호'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _holder,
              decoration: const InputDecoration(labelText: '예금주'),
              validator: (v) => required(v, '예금주'),
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 이번 회차의 마감 일시. 다음 회차부터는 이 마감에서 1주일씩 이어진다.
class _RoundDeadlineForm extends ConsumerStatefulWidget {
  const _RoundDeadlineForm();

  @override
  ConsumerState<_RoundDeadlineForm> createState() => _RoundDeadlineFormState();
}

class _RoundDeadlineFormState extends ConsumerState<_RoundDeadlineForm> {
  /// 고른 날짜 / 시각. null 이면 지금 마감 그대로.
  DateTime? _date;
  TimeOfDay? _time;
  bool _saving = false;

  DateTime _deadline(OrderRound round) {
    final d = _date ?? round.deadline;
    final t = _time ?? TimeOfDay.fromDateTime(round.deadline);
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _pickDate(OrderRound round) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = DateUtils.dateOnly(_deadline(round));
    final picked = await showDatePicker(
      context: context,
      helpText: '마감 날짜',
      initialDate: current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: DateTime(today.year + 1, today.month, today.day - 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(OrderRound round) async {
    final picked = await showTimePicker(
      context: context,
      helpText: '마감 시각',
      initialTime: TimeOfDay.fromDateTime(_deadline(round)),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save(OrderRound round) async {
    final deadline = _deadline(round);
    if (_saving) return;
    if (!deadline.isAfter(DateTime.now())) {
      showErrorSnack(context, const AppException('마감 일시는 지금보다 뒤여야 합니다.'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(textbookRepositoryProvider)
          .setRoundDeadline(round.id, deadline);
      ref.invalidate(adminRoundsProvider);
      ref.invalidate(currentRoundProvider);
      if (!mounted) return;
      setState(() {
        _date = null;
        _time = null;
      });
      showSnack(
        context,
        '이번 회차 마감을 ${DateFormat('M/d(E)').format(deadline)} '
        '${timeLabel(deadline)}(으)로 바꿨습니다.',
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rounds = ref.watch(adminRoundsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('교재 신청 마감'),
          Text(
            '마감 일시가 지나면 다음 회차가 시작됩니다. '
            '다음 회차부터는 같은 요일 · 시각에 1주일 간격으로 마감됩니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          AsyncValueView(
            value: rounds,
            onRetry: () => ref.invalidate(adminRoundsProvider),
            isEmpty: (list) => list == null,
            empty: const EmptyView(message: '신청 회차가 없습니다.'),
            data: (list) => _body(list!.current),
          ),
        ],
      ),
    );
  }

  Widget _body(OrderRound round) {
    final c = context.colors;
    final deadline = _deadline(round);
    final changed = _date != null || _time != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '이번 회차 ${round.label} · ${round.deadlineLabel} 마감',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _pickDate(round),
              icon: const Icon(Icons.event, size: 18),
              label: Text(DateFormat('yyyy. M. d.(E)').format(deadline)),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _pickTime(round),
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(timeLabel(deadline)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (changed)
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _date = null;
                        _time = null;
                      }),
                child: const Text('되돌리기'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: !changed || _saving ? null : () => _save(round),
              child: const Text('마감 저장'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DefaultPasswordInfo extends StatelessWidget {
  const _DefaultPasswordInfo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('기본 비밀번호'),
            Text(
              '회원 관리 > 비밀번호 초기화에 쓰는 기본 비밀번호는 보안을 위해 앱이나 DB 에 저장하지 않고 '
              'Supabase Edge Function 의 secret(DEFAULT_PASSWORD)에만 둡니다.\n'
              '변경: Supabase Dashboard > Edge Functions > Secrets',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
