import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'auth_providers.dart';
import 'widgets/auth_card.dart';

/// 가입 후 관리자 승인을 기다리는 화면. 승인되면 라우터 가드가 원래 화면으로 보낸다.
class PendingApprovalPage extends ConsumerWidget {
  const PendingApprovalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final p = profile.value;
    final theme = Theme.of(context);

    return AuthCard(
      title: '승인 대기 중',
      subtitle: '가입 신청이 접수되었습니다. 회계 담당자가 승인하면 서비스를 이용할 수 있습니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p != null)
            Card(
              color: theme.colorScheme.surfaceContainerHigh,
              child: ListTile(
                leading: const Icon(Icons.hourglass_top),
                title: Text(p.name),
                subtitle: Text('학번 ${p.studentId}'),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '학번이나 이름을 잘못 입력했다면 회계 담당자에게 알려 주세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: profile.isLoading
                ? null
                : () => ref.invalidate(currentProfileProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('승인 여부 다시 확인'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }
}
