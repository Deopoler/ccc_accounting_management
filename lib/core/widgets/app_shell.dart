import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/presentation/account_menu_button.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../router/routes.dart';
import '../theme/app_theme.dart';
import 'responsive.dart';

/// 로그인 후 화면 공통 틀. 데스크톱은 사이드 네비게이션, 모바일은 하단 네비게이션.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final desktop = isDesktop(context);
    final meta = routeMetaFor(location);
    // 데스크톱에서는 사이드 네비게이션에 관리자 메뉴가 모두 보이므로 허브로 돌아갈 필요가 없다.
    final backTo = (desktop && meta.parent == AppRoutes.admin)
        ? null
        : meta.parent;

    final appBar = AppBar(
      automaticallyImplyLeading: false,
      leading: backTo == null
          ? null
          : BackButton(onPressed: () => context.go(backTo)),
      title: Text(meta.title),
      actions: const [AccountMenuButton(), SizedBox(width: 8)],
    );

    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(location: location, isAdmin: isAdmin),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Scaffold(appBar: appBar, body: child),
            ),
          ],
        ),
      );
    }

    final destinations = [
      ...memberDestinations,
      if (isAdmin)
        const NavDestination(
          path: AppRoutes.admin,
          label: '관리',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
        ),
    ];
    final selected = matchDestination(destinations, location);

    return Scaffold(
      appBar: appBar,
      body: child,
      bottomNavigationBar: DecoratedBox(
        // 그림자 대신 얇은 구분선
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.divider)),
        ),
        child: NavigationBar(
          selectedIndex: selected ?? 0,
          onDestinationSelected: (i) => context.go(destinations[i].path),
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.location, required this.isAdmin});

  final String location;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = [...memberDestinations, if (isAdmin) ...adminDestinations];
    final selected = matchDestination(all, location);
    final selectedPath = selected == null ? null : all[selected].path;

    final c = context.colors;
    Widget tile(NavDestination d) {
      final isSelected = d.path == selectedPath;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: ListTile(
          selected: isSelected,
          selectedTileColor: c.surfaceMuted,
          selectedColor: c.textPrimary,
          iconColor: c.textTertiary,
          textColor: c.textSecondary,
          leading: Icon(isSelected ? d.selectedIcon : d.icon),
          title: Text(
            d.label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          onTap: () => context.go(d.path),
        ),
      );
    }

    return SizedBox(
      width: 248,
      // ListTile 의 선택 배경 / 잉크 효과가 보이도록 ColoredBox 가 아닌 Material 로 칠한다.
      child: Material(
        color: c.background,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 16, 20),
                child: Text(
                  'CCC 회계',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              for (final d in memberDestinations) tile(d),
              if (isAdmin) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Divider(height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 16, 8),
                  child: Text(
                    '관리자',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textTertiary,
                    ),
                  ),
                ),
                for (final d in adminDestinations) tile(d),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
