import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/responsive.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../campus/presentation/campus_switcher.dart';

/// 관리자 메뉴 모음. 모바일에서 하단 "관리" 탭의 진입 화면.
class AdminHubPage extends ConsumerWidget {
  const AdminHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCentral = ref.watch(isCentralAdminProvider);
    return ScrollPageBody(
      maxWidth: 720,
      children: [
        if (isCentral) ...[
          LayoutBuilder(
            builder: (context, c) => CampusSwitcher(width: c.maxWidth),
          ),
          const SizedBox(height: 16),
        ],
        for (final d in [
          ...adminDestinations,
          if (isCentral) ...centralDestinations,
        ]) ...[
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              leading: Icon(d.icon),
              title: Text(d.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(d.path),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
