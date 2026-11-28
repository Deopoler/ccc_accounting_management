import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/admin/presentation/admin_badge_providers.dart';
import '../../features/auth/presentation/account_menu_button.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/campus/presentation/campus_switcher.dart';
import '../../features/push/presentation/push_providers.dart';
import '../router/route_revalidation.dart';
import '../router/routes.dart';
import '../theme/app_theme.dart';
import 'focus_ring.dart';
import 'responsive.dart';

/// 로그인 후 화면 공통 틀. 데스크톱은 사이드 네비게이션, 모바일은 하단 네비게이션.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.uri,
    this.navigationShell,
  });

  final String location;
  final Widget child;
  final Uri? uri;
  final StatefulNavigationShell? navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _textbooksBranchIndex = 1;

  Uri? _lastTextbooksUri;

  @override
  void initState() {
    super.initState();
    _recordTextbooksUri();
  }

  Uri get _currentUri => widget.uri ?? Uri.parse(widget.location);

  static bool _sameRevalidationTarget(Uri a, Uri b) =>
      a.path == b.path &&
      a.queryParameters['edit'] == b.queryParameters['edit'] &&
      a.queryParameters['tab'] == b.queryParameters['tab'];

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recordTextbooksUri();
    final oldUri = oldWidget.uri ?? Uri.parse(oldWidget.location);
    final targetUri = _currentUri;
    if (!_sameRevalidationTarget(oldUri, targetUri)) {
      // 새 화면이 그려지기 전에 이미 불러온 것만 골라 둔다(첫 방문은 다시 받지 않는다).
      final loaded = loadedRouteProviders(ref, targetUri);
      if (loaded.isEmpty) return;
      // Wait for TickerMode on the newly active IndexedStack branch to resume
      // before invalidating, so Riverpod refreshes in-place instead of disposing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sameRevalidationTarget(_currentUri, targetUri)) {
          revalidateProviders(ref, loaded);
        }
      });
    }
  }

  void _recordTextbooksUri() {
    if (widget.location == AppRoutes.textbooks ||
        widget.location.startsWith('${AppRoutes.textbooks}/')) {
      _lastTextbooksUri = widget.uri ?? Uri.parse(widget.location);
    }
  }

  void _goBranch(int index) {
    final shell = widget.navigationShell;
    if (shell == null) return;
    final resettingTextbooks =
        index == _textbooksBranchIndex &&
        _lastTextbooksUri != null &&
        (_lastTextbooksUri!.path != AppRoutes.textbooks ||
            _lastTextbooksUri!.queryParameters.containsKey('edit'));
    shell.goBranch(
      index,
      initialLocation: index == shell.currentIndex || resettingTextbooks,
    );
  }

  void _navigateToPath(String path) {
    final shell = widget.navigationShell;
    if (shell != null) {
      final memberIndex = memberDestinations.indexWhere((d) => d.path == path);
      if (memberIndex >= 0) {
        _goBranch(memberIndex);
        return;
      }
    }
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    // 회원이 로그인했을 때 이미 알림 권한이 허용된 기기면 자동으로 구독을 등록한다.
    ref.watch(signupPushProvider);
    final location = widget.location;
    final isAdmin = ref.watch(isAdminProvider);
    final isCentral = ref.watch(isCentralAdminProvider);
    final desktop = isDesktop(context);
    final meta = routeMetaFor(location);
    // 총괄 관리자는 여러 캠퍼스를 오가므로, 관리자 화면 제목에 지금 캠퍼스를 붙인다.
    final campusName = isCentral && _isCampusScopedAdminPath(location)
        ? ref.watch(adminCampusProvider).value?.name
        : null;
    // 데스크톱에서는 사이드 네비게이션에 관리자 메뉴가 모두 보이므로 허브로 돌아갈 필요가 없다.
    final backTo = (desktop && meta.parent == AppRoutes.admin)
        ? null
        : meta.parent;

    final appBar = AppBar(
      automaticallyImplyLeading: false,
      leading: backTo == null
          ? null
          : BackButton(onPressed: () => context.go(backTo)),
      title: Text(
        campusName == null ? meta.title : '${meta.title} · $campusName',
        overflow: TextOverflow.ellipsis,
      ),
      actions: const [AccountMenuButton(), SizedBox(width: 8)],
    );

    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(
              location: location,
              isAdmin: isAdmin,
              isCentral: isCentral,
              onSelect: _navigateToPath,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Scaffold(appBar: appBar, body: widget.child),
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
    final showMobileSwitcher =
        isAdmin && _isMobileAdminSectionPath(location, isCentral: isCentral);

    return Scaffold(
      appBar: appBar,
      body: showMobileSwitcher
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileAdminSectionSwitcher(
                  location: location,
                  isCentral: isCentral,
                  onSelect: _navigateToPath,
                ),
                Expanded(child: widget.child),
              ],
            )
          : widget.child,
      bottomNavigationBar: DecoratedBox(
        // 그림자 대신 얇은 구분선
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.divider)),
        ),
        child: NavigationBar(
          selectedIndex: selected ?? 0,
          onDestinationSelected: (i) {
            if (widget.navigationShell != null) {
              _goBranch(i);
            } else {
              context.go(destinations[i].path);
            }
          },
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: NavFocusIcon(d.icon),
                selectedIcon: NavFocusIcon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// 캠퍼스별 데이터를 다루는 관리자 화면 (허브 / 총괄 관리 제외).
bool _isCampusScopedAdminPath(String location) {
  final path = Uri.parse(location).path;
  return path.startsWith('${AppRoutes.admin}/') &&
      !AppRoutes.centralOnly.any((p) => path == p || path.startsWith('$p/'));
}

/// 모바일 상단 관리자 섹션 전환기를 표시할 상위 관리자 경로인지 판별한다.
bool _isMobileAdminSectionPath(String location, {required bool isCentral}) {
  final path = Uri.parse(location).path;
  final sections = [
    ...adminDestinations,
    if (isCentral) ...centralDestinations,
  ];
  return sections.any((d) => d.path == path);
}

class _NavBadgeSlot extends ConsumerWidget {
  const _NavBadgeSlot({required this.path, this.selected = false});

  final String path;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(adminDestinationBadgeProvider(path));
    if (count == null) return const SizedBox.shrink();
    return AdminCountBadge(count: count, selected: selected);
  }
}

class _MobileAdminSectionSwitcher extends StatelessWidget {
  const _MobileAdminSectionSwitcher({
    required this.location,
    required this.isCentral,
    required this.onSelect,
  });

  final String location;
  final bool isCentral;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sections = [
      ...adminDestinations,
      if (isCentral) ...centralDestinations,
    ];
    final selected = matchDestination(sections, location);
    final selectedPath = selected == null ? null : sections[selected].path;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _MobileSectionChip(
                destination: sections[i],
                selected: sections[i].path == selectedPath,
                onTap: () => onSelect(sections[i].path),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MobileSectionChip extends ConsumerWidget {
  const _MobileSectionChip({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final badge = ref.watch(adminDestinationBadgeProvider(destination.path));
    final fg = selected ? c.primary : c.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      child: FocusRing(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Material(
          color: selected ? c.primarySoft : c.surfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            side: selected
                ? BorderSide(color: c.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 18,
                    color: fg,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    destination.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    AdminCountBadge(count: badge, selected: selected),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.location,
    required this.isAdmin,
    required this.isCentral,
    required this.onSelect,
  });

  final String location;
  final bool isAdmin;
  final bool isCentral;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = [
      ...memberDestinations,
      if (isAdmin) ...adminDestinations,
      if (isCentral) ...centralDestinations,
    ];
    final selected = matchDestination(all, location);
    final selectedPath = selected == null ? null : all[selected].path;

    final c = context.colors;
    Widget tile(NavDestination d, {bool showBadge = false}) {
      final isSelected = d.path == selectedPath;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: FocusRing(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ListTile(
            selected: isSelected,
            selectedTileColor: c.primarySoft,
            selectedColor: c.primary,
            iconColor: c.textTertiary,
            textColor: c.textSecondary,
            leading: Icon(isSelected ? d.selectedIcon : d.icon),
            title: Text(
              d.label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: showBadge
                ? _NavBadgeSlot(path: d.path, selected: isSelected)
                : null,
            onTap: () => onSelect(d.path),
          ),
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
                if (isCentral)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 4, 12, 8),
                    child: CampusSwitcher(width: 200),
                  ),
                for (final d in adminDestinations) tile(d, showBadge: true),
                if (isCentral)
                  for (final d in centralDestinations) tile(d, showBadge: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
