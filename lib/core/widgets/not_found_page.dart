import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../router/routes.dart';
import 'state_views.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyView(
        icon: Icons.explore_off_outlined,
        message: '페이지를 찾을 수 없습니다.',
        action: FilledButton(
          onPressed: () => context.go(AppRoutes.home),
          child: const Text('홈으로'),
        ),
      ),
    );
  }
}
