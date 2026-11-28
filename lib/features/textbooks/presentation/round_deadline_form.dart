import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/josa.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../campus/presentation/campus_providers.dart';
import '../domain/order_round.dart';
import 'textbook_providers.dart';

/// 이번 회차 마감 일시 변경 다이얼로그.
Future<void> showRoundDeadlineDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('교재 신청 마감'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: const SingleChildScrollView(
          child: RoundDeadlineForm(showHeader: false),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}

/// 이번 회차의 마감 일시. 다음 회차부터는 이 마감에서 1주일씩 이어진다.
class RoundDeadlineForm extends ConsumerStatefulWidget {
  const RoundDeadlineForm({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  ConsumerState<RoundDeadlineForm> createState() => _RoundDeadlineFormState();
}

class _RoundDeadlineFormState extends ConsumerState<RoundDeadlineForm> {
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
      ref.invalidate(adminCurrentRoundProvider);
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
        '${withRo(timeLabel(deadline))} 바꿨습니다.',
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCampusId = ref.watch(adminCampusIdProvider);
    final currentRound = ref.watch(adminCurrentRoundProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader) const SectionTitle('교재 신청 마감'),
          Text(
            '마감 일시가 지나면 다음 회차가 시작됩니다. '
            '다음 회차부터는 같은 요일 · 시각에 1주일 간격으로 마감됩니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          AsyncValueView(
            value: activeCampusId == null
                ? const AsyncLoading<OrderRound?>()
                : currentRound,
            showRefreshIndicator: false,
            loading: const RoundDeadlinePlaceholder(),
            onRetry: () => ref.invalidate(adminCurrentRoundProvider),
            isEmpty: (round) => round == null,
            empty: const EmptyView(message: '신청 회차가 없습니다.'),
            data: (round) => _body(round!),
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
      mainAxisSize: MainAxisSize.min,
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

class RoundDeadlinePlaceholder extends StatelessWidget {
  const RoundDeadlinePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SkeletonText(maxWidth: 220, fontSize: 14),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.event, size: 18),
              label: const SkeletonBox(width: 96, height: 14, announce: false),
            ),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.schedule, size: 18),
              label: const SkeletonBox(width: 64, height: 14, announce: false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: null, child: const Text('마감 저장')),
        ),
      ],
    );
  }
}
