import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../textbooks/domain/textbook.dart';
import '../../textbooks/presentation/textbook_providers.dart';

class AdminTextbooksPage extends ConsumerWidget {
  const AdminTextbooksPage({super.key});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      ref.invalidate(textbooksProvider);
      if (context.mounted && success != null) showSnack(context, success);
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      if (e.code == '23503') {
        showSnack(context, '이미 신청된 교재는 삭제할 수 없습니다. 대신 "신청 가능"을 꺼 주세요.');
      } else {
        showErrorSnack(context, e);
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showTextbookFormDialog(context);
    if (input == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).createTextbook(input),
      success: '교재를 추가했습니다.',
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Textbook t) async {
    final input = await showTextbookFormDialog(context, initial: t);
    if (input == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).updateTextbook(t.id, input),
      success: '교재를 수정했습니다.',
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Textbook t) async {
    final ok = await showConfirmDialog(
      context,
      title: '교재 삭제',
      message: '"${t.title}"을(를) 삭제하시겠습니까?',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).deleteTextbook(t.id),
      success: '교재를 삭제했습니다.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textbooks = ref.watch(textbooksProvider);

    return AsyncValueView(
      value: textbooks,
      onRetry: () => ref.invalidate(textbooksProvider),
      data: (list) => ScrollPageBody(
        maxWidth: 900,
        children: [
          SectionTitle(
            '교재 ${list.length}종',
            trailing: FilledButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('교재 추가'),
            ),
          ),
          if (list.isEmpty)
            const EmptyView(
              icon: Icons.library_books_outlined,
              message: '등록된 교재가 없습니다. 교재를 추가해 주세요.',
            ),
          for (final t in list) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(formatWon(t.price)),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: t.isActive,
                          onChanged: (v) => _run(
                            context,
                            ref,
                            () => ref
                                .read(textbookRepositoryProvider)
                                .setTextbookActive(t.id, isActive: v),
                          ),
                        ),
                        Text(
                          t.isActive ? '신청 가능' : '신청 불가',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '수정',
                      onPressed: () => _edit(context, ref, t),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '삭제',
                      onPressed: () => _delete(context, ref, t),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

Future<TextbookInput?> showTextbookFormDialog(
  BuildContext context, {
  Textbook? initial,
}) {
  return showDialog<TextbookInput>(
    context: context,
    builder: (_) => _TextbookFormDialog(initial: initial),
  );
}

class _TextbookFormDialog extends StatefulWidget {
  const _TextbookFormDialog({this.initial});

  final Textbook? initial;

  @override
  State<_TextbookFormDialog> createState() => _TextbookFormDialogState();
}

class _TextbookFormDialogState extends State<_TextbookFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _price = TextEditingController(
    text: widget.initial?.price.toString(),
  );
  late bool _active = widget.initial?.isActive ?? true;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      TextbookInput(
        title: _title.text.trim(),
        price: int.parse(_price.text),
        isActive: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '교재 추가' : '교재 수정'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '교재명'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '교재명을 입력해 주세요.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(
                  labelText: '가격',
                  suffixText: '원',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null) return '가격을 입력해 주세요.';
                  if (n > 10000000) return '가격이 너무 큽니다.';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('신청 가능'),
                subtitle: const Text('끄면 회원이 이 교재를 신청할 수 없습니다.'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}
