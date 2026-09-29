import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import 'auth_providers.dart';

/// 앱바의 "내 정보" 메뉴: 학번/이름 표시, 비밀번호 변경, 로그아웃.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;

    return PopupMenuButton<String>(
      tooltip: '내 정보',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) {
        switch (value) {
          case 'password':
            context.push(AppRoutes.changePassword);
          case 'logout':
            ref.read(authRepositoryProvider).signOut();
        }
      },
      itemBuilder: (context) => [
        if (profile != null)
          PopupMenuItem(
            enabled: false,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(profile.name),
              subtitle: Text('${profile.studentId} · ${profile.role.label}'),
            ),
          ),
        if (profile != null) const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'password',
          child: ListTile(
            leading: Icon(Icons.lock_reset),
            title: Text('비밀번호 변경'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('로그아웃'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
