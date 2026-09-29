import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import 'auth_providers.dart';

/// 앱바의 "내 정보" 메뉴: 학번/이름 표시, 화면 테마, 비밀번호 변경, 로그아웃.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    final themeMode = ref.watch(themeModeProvider);

    return PopupMenuButton<String>(
      tooltip: '내 정보',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) {
        switch (value) {
          case 'theme':
            showThemeModeSheet(context);
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
              title: Text(
                profile.name,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${profile.studentId} · ${profile.role.label}',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
        if (profile != null) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            leading: Icon(themeMode.icon),
            title: const Text('화면 테마'),
            // 메뉴 폭이 좁아 현재 설정은 오른쪽이 아니라 아래에 둔다. (제목 줄바꿈 방지)
            subtitle: Text(
              themeMode.label,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
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

/// 화면 테마 선택 (시스템 설정 / 라이트 / 다크)
Future<void> showThemeModeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.colors.elevatedSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(themeModeProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Text(
                    '화면 테마',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (final mode in ThemeMode.values)
                  ListTile(
                    leading: Icon(mode.icon),
                    title: Text(mode.label),
                    trailing: mode == current
                        ? Icon(Icons.check, color: context.colors.primary)
                        : null,
                    onTap: () {
                      ref.read(themeModeProvider.notifier).set(mode);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
