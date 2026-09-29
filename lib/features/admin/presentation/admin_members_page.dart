import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../textbooks/presentation/widgets/order_widgets.dart';
import 'member_providers.dart';

/// 회원 관리: 가입 승인, 관리자 지정.
class AdminMembersPage extends ConsumerStatefulWidget {
  const AdminMembersPage({super.key});

  @override
  ConsumerState<AdminMembersPage> createState() => _AdminMembersPageState();
}

class _AdminMembersPageState extends ConsumerState<AdminMembersPage> {
  final Set<String> _selected = {};
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(membersProvider);
      if (mounted) showSnack(context, success);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Set<String> ids) async {
    await _run(
      () => ref.read(memberRepositoryProvider).approve(ids),
      '${ids.length}명을 승인했습니다.',
    );
    _selected.removeAll(ids);
  }

  /// Edge Function 호출 결과 메시지를 보여준다.
  Future<void> _runFunction(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      ref.invalidate(membersProvider);
      if (mounted) showSnack(context, message);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Profile m) async {
    final ok = await showConfirmDialog(
      context,
      title: '가입 거절',
      message:
          '${m.name}(${m.studentId})의 가입 신청을 거절하고 계정을 삭제합니다. '
          '본인이 다시 가입할 수 있습니다.',
      confirmLabel: '거절',
      destructive: true,
    );
    if (!ok) return;
    await _runFunction(
      () => ref.read(memberRepositoryProvider).rejectSignup(m.id),
    );
  }

  Future<void> _resetPassword(Profile m) async {
    final ok = await showConfirmDialog(
      context,
      title: '비밀번호 초기화',
      message:
          '${m.name}(${m.studentId})의 비밀번호를 기본 비밀번호로 초기화합니다. '
          '다음 로그인 때 새 비밀번호로 변경해야 합니다. '
          '기본 비밀번호는 회원에게 직접 알려 주세요.',
      confirmLabel: '초기화',
      destructive: true,
    );
    if (!ok) return;
    await _runFunction(
      () => ref.read(memberRepositoryProvider).resetPassword(m.id),
    );
  }

  Future<void> _toggleAdmin(Profile m) async {
    final toAdmin = m.role != UserRole.admin;
    final ok = await showConfirmDialog(
      context,
      title: toAdmin ? '관리자 지정' : '관리자 해제',
      message: toAdmin
          ? '${m.name}(${m.studentId})에게 관리자 권한을 줍니다. 모든 회계 데이터를 보고 수정할 수 있게 됩니다.'
          : '${m.name}(${m.studentId})의 관리자 권한을 해제합니다.',
      confirmLabel: toAdmin ? '지정' : '해제',
      destructive: !toAdmin,
    );
    if (!ok) return;
    await _run(
      () => ref
          .read(memberRepositoryProvider)
          .setRole(m.id, toAdmin ? UserRole.admin : UserRole.member),
      toAdmin ? '관리자로 지정했습니다.' : '관리자 권한을 해제했습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    final me = ref.watch(currentUserIdProvider);

    return AsyncValueView(
      value: members,
      onRetry: () => ref.invalidate(membersProvider),
      data: (all) {
        final pending = all.where((m) => !m.isApproved).toList();
        final q = _search.text.trim().toLowerCase();
        final approved = all
            .where((m) => m.isApproved)
            .where(
              (m) =>
                  q.isEmpty ||
                  m.name.toLowerCase().contains(q) ||
                  m.studentId.toLowerCase().contains(q),
            )
            .toList();
        // 목록에서 사라진 회원은 선택에서도 뺀다.
        _selected.retainWhere((id) => pending.any((m) => m.id == id));

        return ScrollPageBody(
          maxWidth: 900,
          children: [
            _PendingSection(
              pending: pending,
              selected: _selected,
              busy: _busy,
              onSelect: (id, v) =>
                  setState(() => v ? _selected.add(id) : _selected.remove(id)),
              onSelectAll: (v) => setState(
                () => v
                    ? _selected.addAll(pending.map((m) => m.id))
                    : _selected.clear(),
              ),
              onApprove: _approve,
              onReject: _reject,
            ),
            const SizedBox(height: 24),
            SectionTitle(
              '회원 ${all.where((m) => m.isApproved).length}명',
              trailing: SizedBox(
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
            ),
            if (approved.isEmpty)
              const EmptyView(message: '해당하는 회원이 없습니다.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, m) in approved.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Row(
                          children: [
                            Flexible(child: Text(m.name)),
                            if (m.isAdmin) ...[
                              const SizedBox(width: 8),
                              StatusBadge(
                                label: '관리자',
                                background: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                foreground: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${m.studentId} · 가입 ${formatDate(m.createdAt)}',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: '더보기',
                          enabled: !_busy && m.id != me,
                          onSelected: (v) => v == 'reset'
                              ? _resetPassword(m)
                              : _toggleAdmin(m),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'reset',
                              child: Text('비밀번호 초기화'),
                            ),
                            PopupMenuItem(
                              value: 'role',
                              child: Text(m.isAdmin ? '관리자 해제' : '관리자로 지정'),
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
      },
    );
  }
}

class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.pending,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onSelectAll,
    required this.onApprove,
    required this.onReject,
  });

  final List<Profile> pending;
  final Set<String> selected;
  final bool busy;
  final void Function(String id, bool value) onSelect;
  final ValueChanged<bool> onSelectAll;
  final Future<void> Function(Set<String> ids) onApprove;
  final Future<void> Function(Profile member) onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = pending.isNotEmpty && selected.length == pending.length;

    return Card(
      color: pending.isEmpty
          ? null
          : theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              '가입 승인 대기 ${pending.length}명',
              trailing: pending.isEmpty
                  ? null
                  : FilledButton(
                      onPressed: busy || selected.isEmpty
                          ? null
                          : () => onApprove({...selected}),
                      child: Text('선택 승인 (${selected.length})'),
                    ),
            ),
            if (pending.isEmpty)
              Text('승인을 기다리는 가입 신청이 없습니다.', style: theme.textTheme.bodyMedium)
            else ...[
              Text(
                '학번과 이름이 실제 회원과 일치하는지 확인한 뒤 승인해 주세요. '
                '승인하면 진행 중인 이벤트의 송금 대상으로 자동 등록됩니다.',
                style: theme.textTheme.bodySmall,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: allSelected ? true : (selected.isEmpty ? false : null),
                tristate: true,
                onChanged: busy ? null : (_) => onSelectAll(!allSelected),
                title: const Text('전체 선택'),
              ),
              const Divider(height: 1),
              for (final m in pending)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selected.contains(m.id),
                  onChanged: busy ? null : (v) => onSelect(m.id, v ?? false),
                  title: Text('${m.name}  ${m.studentId}'),
                  subtitle: Text('가입 ${formatDateTime(m.createdAt)}'),
                  secondary: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => onReject(m),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child: const Text('거절'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => onApprove({m.id}),
                        child: const Text('승인'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
