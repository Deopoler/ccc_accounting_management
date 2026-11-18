import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/feedback_entry.dart';
import 'feedback_providers.dart';

/// 피드백함 (총괄 관리자). 회원이 보낸 피드백을 최신순으로 보고 확인 처리한다.
class AdminFeedbackPage extends ConsumerStatefulWidget {
  const AdminFeedbackPage({super.key});

  @override
  ConsumerState<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends ConsumerState<AdminFeedbackPage> {
  final Set<String> _busy = {};

  Future<void> _setResolved(FeedbackEntry entry, bool resolved) async {
    if (_busy.contains(entry.id)) return;
    setState(() => _busy.add(entry.id));
    try {
      await ref
          .read(feedbackRepositoryProvider)
          .setResolved(entry.id, resolved: resolved);
      ref.invalidate(feedbackListProvider);
      if (mounted) {
        showSnack(context, resolved ? '확인 처리했습니다.' : '확인을 취소했습니다.');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(feedbackFilterProvider);
    final list = ref.watch(feedbackListProvider);

    return ScrollPageBody(
      maxWidth: 720,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in FeedbackFilter.values)
              ChoiceChip(
                label: Text(f.label),
                selected: filter == f,
                onSelected: (_) =>
                    ref.read(feedbackFilterProvider.notifier).select(f),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (list.hasError)
          ErrorView(
            error: list.error!,
            onRetry: () => ref.invalidate(feedbackListProvider),
          )
        else if (!list.hasValue)
          const LoadingView()
        else if (list.requireValue.isEmpty)
          EmptyView(
            icon: Icons.inbox_outlined,
            message: filter == FeedbackFilter.unresolved
                ? '확인하지 않은 피드백이 없습니다.'
                : '받은 피드백이 없습니다.',
          )
        else
          for (final entry in list.requireValue) ...[
            _FeedbackCard(
              entry: entry,
              busy: _busy.contains(entry.id),
              onToggle: (resolved) => _setResolved(entry, resolved),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.entry,
    required this.busy,
    required this.onToggle,
  });

  final FeedbackEntry entry;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final sender = [
      if (entry.senderName.isNotEmpty) entry.senderName,
      if (entry.senderStudentId.isNotEmpty) '(${entry.senderStudentId})',
    ].join(' ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sender.isEmpty ? '알 수 없는 회원' : sender,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (entry.campusName.isNotEmpty) entry.campusName,
                formatDateTime(entry.createdAt),
              ].join(' · '),
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 12),
            SelectableText(entry.content, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.resolvedAt == null
                        ? '미확인'
                        : '확인 ${formatDateTime(entry.resolvedAt!)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: entry.isResolved ? c.textTertiary : c.primary,
                    ),
                  ),
                ),
                Text(
                  '확인',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: entry.isResolved,
                  onChanged: busy ? null : onToggle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
