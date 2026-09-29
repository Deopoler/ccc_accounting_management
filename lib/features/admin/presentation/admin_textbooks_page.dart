import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../textbooks/domain/textbook.dart';
import '../../textbooks/domain/textbook_category.dart';
import '../../textbooks/presentation/textbook_providers.dart';

/// 교재 관리: 카테고리(추가 / 이름 변경 / 순서 / 삭제)와 카테고리별 교재.
class AdminTextbooksPage extends ConsumerWidget {
  const AdminTextbooksPage({super.key});

  /// 작업 실행 후 목록을 새로 고친다. [fkMessage] 는 참조 중이라 삭제가 거부됐을 때(23503)의 안내.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    String? success,
    String? fkMessage,
  }) async {
    try {
      await action();
      if (context.mounted && success != null) showSnack(context, success);
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      if (e.code == '23503' && fkMessage != null) {
        showSnack(context, fkMessage);
      } else {
        showErrorSnack(context, e);
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    } finally {
      ref
        ..invalidate(textbooksProvider)
        ..invalidate(textbookCategoriesProvider);
    }
  }

  // ---------------------------------------------------------------- 카테고리

  Future<void> _createCategory(
    BuildContext context,
    WidgetRef ref,
    List<TextbookCategory> categories,
  ) async {
    final name = await showNameDialog(context, title: '카테고리 추가');
    if (name == null || !context.mounted) return;
    final next = categories.isEmpty
        ? 0
        : categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) +
              1;
    await _run(
      context,
      ref,
      () => ref
          .read(textbookRepositoryProvider)
          .createCategory(name, sortOrder: next),
      success: '카테고리를 추가했습니다.',
    );
  }

  Future<void> _renameCategory(
    BuildContext context,
    WidgetRef ref,
    TextbookCategory c,
  ) async {
    final name = await showNameDialog(
      context,
      title: '카테고리 이름 변경',
      initial: c.name,
    );
    if (name == null || name == c.name || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).renameCategory(c.id, name),
      success: '이름을 바꿨습니다.',
    );
  }

  Future<void> _deleteCategory(
    BuildContext context,
    WidgetRef ref,
    TextbookCategory c,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '카테고리 삭제',
      message: '"${c.name}" 카테고리를 삭제하시겠습니까?',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).deleteCategory(c.id),
      success: '카테고리를 삭제했습니다.',
      fkMessage: '교재가 있는 카테고리는 삭제할 수 없습니다. 교재를 다른 카테고리로 옮긴 뒤 삭제해 주세요.',
    );
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    List<TextbookCategory> ordered,
    int index,
    int delta,
  ) async {
    final ids = ordered.map((c) => c.id).toList();
    final target = index + delta;
    if (target < 0 || target >= ids.length) return;
    final moved = ids.removeAt(index);
    ids.insert(target, moved);
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).reorderCategories(ids),
    );
  }

  // ---------------------------------------------------------------- 교재

  Future<void> _createTextbook(
    BuildContext context,
    WidgetRef ref,
    List<TextbookCategory> categories, {
    String? categoryId,
  }) async {
    final input = await showTextbookFormDialog(
      context,
      categories: categories,
      initialCategoryId: categoryId,
    );
    if (input == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).createTextbook(input),
      success: '교재를 추가했습니다.',
    );
  }

  Future<void> _editTextbook(
    BuildContext context,
    WidgetRef ref,
    List<TextbookCategory> categories,
    Textbook t,
  ) async {
    final input = await showTextbookFormDialog(
      context,
      categories: categories,
      initial: t,
    );
    if (input == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(textbookRepositoryProvider).updateTextbook(t.id, input),
      success: '교재를 수정했습니다.',
    );
  }

  Future<void> _deleteTextbook(
    BuildContext context,
    WidgetRef ref,
    Textbook t,
  ) async {
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
      fkMessage: '이미 신청된 교재는 삭제할 수 없습니다. 대신 "신청 가능"을 꺼 주세요.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textbooks = ref.watch(textbooksProvider);
    final categories = ref.watch(textbookCategoriesProvider);

    if (textbooks.hasError || categories.hasError) {
      return ErrorView(
        error: (textbooks.error ?? categories.error)!,
        onRetry: () {
          ref.invalidate(textbooksProvider);
          ref.invalidate(textbookCategoriesProvider);
        },
      );
    }
    if (!textbooks.hasValue || !categories.hasValue) {
      return const LoadingView();
    }

    final books = textbooks.requireValue;
    final cats = categories.requireValue;
    final groups = groupByCategory(cats, books, includeEmpty: true);
    final ordered = [for (final g in groups) ?g.category];
    final theme = Theme.of(context);

    return ScrollPageBody(
      maxWidth: 900,
      children: [
        // ---- 카테고리
        SectionTitle(
          '카테고리 ${cats.length}개',
          trailing: OutlinedButton.icon(
            onPressed: () => _createCategory(context, ref, cats),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('카테고리 추가'),
          ),
        ),
        if (cats.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '카테고리가 없으면 모든 교재가 "$uncategorizedName"로 보입니다.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, c) in ordered.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 4),
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(c.name),
                    subtitle: Text(
                      '교재 ${books.where((t) => t.categoryId == c.id).length}종',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '위로',
                          visualDensity: VisualDensity.compact,
                          onPressed: i == 0
                              ? null
                              : () => _move(context, ref, ordered, i, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: '아래로',
                          visualDensity: VisualDensity.compact,
                          onPressed: i == ordered.length - 1
                              ? null
                              : () => _move(context, ref, ordered, i, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '더보기',
                          onSelected: (v) => v == 'rename'
                              ? _renameCategory(context, ref, c)
                              : _deleteCategory(context, ref, c),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('이름 변경'),
                            ),
                            PopupMenuItem(value: 'delete', child: Text('삭제')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),

        // ---- 교재
        SectionTitle(
          '교재 ${books.length}종',
          trailing: FilledButton.icon(
            onPressed: () => _createTextbook(context, ref, cats),
            icon: const Icon(Icons.add),
            label: const Text('교재 추가'),
          ),
        ),
        if (books.isEmpty)
          const EmptyView(
            icon: Icons.library_books_outlined,
            message: '등록된 교재가 없습니다. 교재를 추가해 주세요.',
          ),
        for (final g in groups)
          if (g.textbooks.isNotEmpty || g.category != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${g.name} (${g.textbooks.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _createTextbook(
                      context,
                      ref,
                      cats,
                      categoryId: g.category?.id,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('여기에 추가'),
                  ),
                ],
              ),
            ),
            if (g.textbooks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('교재가 없습니다.', style: theme.textTheme.bodySmall),
              ),
            for (final t in g.textbooks) ...[
              _TextbookRow(
                textbook: t,
                onToggleActive: (v) => _run(
                  context,
                  ref,
                  () => ref
                      .read(textbookRepositoryProvider)
                      .setTextbookActive(t.id, isActive: v),
                ),
                onEdit: () => _editTextbook(context, ref, cats, t),
                onDelete: () => _deleteTextbook(context, ref, t),
              ),
              const SizedBox(height: 8),
            ],
          ],
      ],
    );
  }
}

class _TextbookRow extends StatelessWidget {
  const _TextbookRow({
    required this.textbook,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
  });

  final Textbook textbook;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = textbook;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: Theme.of(context).textTheme.titleMedium),
                  Text(formatWon(t.price)),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: t.isActive, onChanged: onToggleActive),
                Text(
                  t.isActive ? '신청 가능' : '신청 불가',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '수정',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: '삭제',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 이름 한 줄 입력 창 (카테고리 추가 / 이름 변경).
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _name.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '이름'),
            validator: (v) {
              final n = v?.trim() ?? '';
              if (n.isEmpty) return '이름을 입력해 주세요.';
              if (n.length > 50) return '50자 이하로 입력해 주세요.';
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
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

Future<TextbookInput?> showTextbookFormDialog(
  BuildContext context, {
  required List<TextbookCategory> categories,
  Textbook? initial,
  String? initialCategoryId,
}) {
  return showDialog<TextbookInput>(
    context: context,
    builder: (_) => _TextbookFormDialog(
      categories: categories,
      initial: initial,
      initialCategoryId: initialCategoryId,
    ),
  );
}

class _TextbookFormDialog extends StatefulWidget {
  const _TextbookFormDialog({
    required this.categories,
    this.initial,
    this.initialCategoryId,
  });

  final List<TextbookCategory> categories;
  final Textbook? initial;
  final String? initialCategoryId;

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
  late String? _categoryId = _initialCategory();

  String? _initialCategory() {
    final known = {for (final c in widget.categories) c.id};
    final id = widget.initial != null
        ? widget.initial!.categoryId
        : widget.initialCategoryId;
    return known.contains(id) ? id : null;
  }

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
        categoryId: _categoryId,
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
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: '카테고리'),
                items: [
                  for (final c in widget.categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                  const DropdownMenuItem(
                    value: null,
                    child: Text('$uncategorizedName (카테고리 없음)'),
                  ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),
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
