import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../admin/presentation/admin_textbooks_page.dart' show showNameDialog;
import '../data/campus_repository.dart';
import '../domain/campus.dart';
import 'campus_providers.dart';
import 'campus_switcher.dart';

/// 총괄 관리자: 캠퍼스 추가 / 이름 변경 / 관리할 캠퍼스 고르기.
/// 캠퍼스 관리자 지정은 캠퍼스를 고른 뒤 회원 관리에서 한다.
class AdminCampusesPage extends ConsumerWidget {
  const AdminCampusesPage({super.key});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      ref.invalidate(campusesProvider);
      if (context.mounted) showSnack(context, success);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<({String code, String name})>(
      context: context,
      builder: (_) => const _NewCampusDialog(),
    );
    if (input == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref
          .read(campusRepositoryProvider)
          .createCampus(code: input.code, name: input.name),
      '${input.name} 캠퍼스를 추가했습니다.',
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Campus c) async {
    final name = await showNameDialog(
      context,
      title: '캠퍼스 이름 변경',
      initial: c.name,
    );
    if (name == null || name == c.name || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(campusRepositoryProvider).renameCampus(c.id, name),
      '캠퍼스 이름을 바꿨습니다.',
    );
  }

  void _manage(BuildContext context, WidgetRef ref, Campus c) {
    ref.read(centralCampusOverrideProvider.notifier).select(c.id);
    showSnack(context, '${c.name} 캠퍼스를 관리합니다.');
    context.go(AppRoutes.adminMembers);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campuses = ref.watch(campusesProvider);
    final current = ref.watch(adminCampusProvider).value;

    return AsyncValueView(
      value: campuses,
      onRetry: () => ref.invalidate(campusesProvider),
      data: (list) => ScrollPageBody(
        maxWidth: 800,
        children: [
          SectionTitle(
            '캠퍼스 ${list.length}곳',
            trailing: FilledButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('캠퍼스 추가'),
            ),
          ),
          Text(
            '캠퍼스를 고르면 관리자 화면(회원 / 교재 / 신청 / 이벤트 / 설정)이 그 캠퍼스로 바뀝니다. '
            '캠퍼스 관리자는 회원 관리에서 지정합니다.',
            style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, c) in list.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Row(
                      children: [
                        Flexible(child: Text(c.name)),
                        if (c.id == current?.id) ...[
                          const SizedBox(width: 8),
                          const AppBadge('관리 중', tone: BadgeTone.accent),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '코드 ${c.code} · 로그인 아이디 학번@${c.emailDomain}',
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: '더보기',
                      onSelected: (v) => v == 'manage'
                          ? _manage(context, ref, c)
                          : _rename(context, ref, c),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'manage',
                          child: Text('이 캠퍼스 관리하기'),
                        ),
                        PopupMenuItem(value: 'rename', child: Text('이름 변경')),
                      ],
                    ),
                    onTap: () => _manage(context, ref, c),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewCampusDialog extends StatefulWidget {
  const _NewCampusDialog();

  @override
  State<_NewCampusDialog> createState() => _NewCampusDialogState();
}

class _NewCampusDialogState extends State<_NewCampusDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (
      code: _code.text.trim().toLowerCase(),
      name: _name.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final code = _code.text.trim().toLowerCase();
    return AlertDialog(
      title: const Text('캠퍼스 추가'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '이름 (예: 서울대)'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return '이름을 입력해 주세요.';
                  if (t.length > 50) return '이름이 너무 깁니다.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                decoration: InputDecoration(
                  labelText: '코드 (예: snu)',
                  helperText: code.isEmpty || validateCampusCode(code) != null
                      ? '로그인 아이디에 쓰이며 나중에 바꿀 수 없습니다.'
                      : '로그인 아이디: 학번@$code.ccc.local (바꿀 수 없음)',
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
                validator: validateCampusCode,
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
        FilledButton(onPressed: _submit, child: const Text('추가')),
      ],
    );
  }
}
