import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../campus/presentation/campus_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/event_providers.dart';
import '../../events/presentation/widgets/event_widgets.dart';

class AdminEventsPage extends ConsumerWidget {
  const AdminEventsPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showEventFormDialog(context);
    if (input == null || !context.mounted) return;
    try {
      final id = await ref
          .read(eventRepositoryProvider)
          .createEvent(await ref.requireAdminCampusId(), input);
      ref
        ..invalidate(eventsProvider)
        ..invalidate(eventSummariesProvider);
      if (context.mounted) {
        showSnack(context, '이벤트를 만들었습니다. 송금 대상을 추가해 주세요.');
        context.go(AppRoutes.adminEventDetail(id));
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(CampusScope.admin));
    final summaries = ref.watch(eventSummariesProvider);

    if (events.hasError || summaries.hasError) {
      return ErrorView(
        error: (events.error ?? summaries.error)!,
        onRetry: () {
          ref.invalidate(eventsProvider);
          ref.invalidate(eventSummariesProvider);
        },
      );
    }
    if (!events.hasValue || !summaries.hasValue) return const LoadingView();

    final list = events.requireValue;
    final sums = summaries.requireValue;

    return ScrollPageBody(
      maxWidth: 900,
      children: [
        SectionTitle(
          '이벤트 ${list.length}개',
          trailing: FilledButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('이벤트 추가'),
          ),
        ),
        if (list.isEmpty)
          const EmptyView(
            icon: Icons.event_note_outlined,
            message: '등록된 이벤트가 없습니다.',
          ),
        for (final e in list) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.go(AppRoutes.adminEventDetail(e.id)),
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
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    const SizedBox(height: 4),
                    EventMetaLine(event: e),
                    const SizedBox(height: 12),
                    PaymentProgress(summary: sums[e.id] ?? EventSummary.empty),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

Future<EventInput?> showEventFormDialog(
  BuildContext context, {
  Event? initial,
}) {
  return showDialog<EventInput>(
    context: context,
    builder: (_) => _EventFormDialog(initial: initial),
  );
}

class _EventFormDialog extends StatefulWidget {
  const _EventFormDialog({this.initial});

  final Event? initial;

  @override
  State<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<_EventFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _amount = TextEditingController(
    text: widget.initial?.amount.toString(),
  );
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final _depositName = TextEditingController(
    text: widget.initial?.depositName,
  );
  late DateTime? _dueDate = widget.initial?.dueDate;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _description.dispose();
    _depositName.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      EventInput(
        title: _title.text.trim(),
        amount: int.parse(_amount.text),
        dueDate: _dueDate,
        description: _description.text.trim(),
        depositName: _depositName.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.initial == null;
    return AlertDialog(
      title: Text(creating ? '이벤트 추가' : '이벤트 수정'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (creating) ...[
                  Text(
                    '만든 뒤 이벤트 화면에서 송금 대상을 추가합니다.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '이벤트명'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '이벤트명을 입력해 주세요.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(
                    labelText: '금액 (1인)',
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
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: const InputDecoration(labelText: '마감일'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dueDate == null ? '없음' : formatDate(_dueDate!),
                        ),
                      ),
                      if (_dueDate != null)
                        IconButton(
                          tooltip: '마감일 없음',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _dueDate = null),
                          icon: const Icon(Icons.clear, size: 18),
                        ),
                      TextButton(onPressed: _pickDate, child: const Text('선택')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _depositName,
                  decoration: InputDecoration(
                    labelText: '입금자명',
                    hintText: '예) {이름}MT',
                    helperText:
                        '${depositNamePlaceholders.join(', ')} 사용 가능 · 비우면 회원 이름\n'
                        '미리보기: 홍길동 → ${renderDepositName(_depositName.text, name: '홍길동', studentId: '20240001')}',
                    helperMaxLines: 2,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      (v?.trim().length ?? 0) > 50 ? '50자 이하로 입력해 주세요.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: '설명'),
                  minLines: 2,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}
