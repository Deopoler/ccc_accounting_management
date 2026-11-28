import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/focus_ring.dart';
import '../../../core/widgets/responsive.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_switcher.dart';
import 'admin_badge_providers.dart';

/// 관리자 메뉴 모음. 모바일에서 하단 "관리" 탭의 진입 화면.
class AdminHubPage extends ConsumerWidget {
  const AdminHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCentral = ref.watch(isCentralAdminProvider);
    final destinations = [
      ...adminDestinations,
      if (isCentral) ...centralDestinations,
    ];

    return ScrollPageBody(
      maxWidth: 720,
      children: [
        if (isCentral) ...[
          LayoutBuilder(
            builder: (context, c) => CampusSwitcher(width: c.maxWidth),
          ),
          const SizedBox(height: 16),
        ],
        for (final d in destinations) ...[
          _AdminHubTile(destination: d),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _AdminHubTile extends ConsumerWidget {
  const _AdminHubTile({required this.destination});

  final NavDestination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = ref.watch(adminDestinationBadgeProvider(destination.path));
    return FocusRing(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: Icon(destination.icon),
          title: Text(
            destination.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: destination.subtitle == null
              ? null
              : Text(destination.subtitle!),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[
                AdminCountBadge(count: badge),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => context.go(destination.path),
        ),
      ),
    );
  }
}
