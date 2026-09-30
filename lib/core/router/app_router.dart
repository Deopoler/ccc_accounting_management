import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/admin/presentation/admin_event_detail_page.dart';
import '../../features/admin/presentation/admin_events_page.dart';
import '../../features/admin/presentation/admin_hub_page.dart';
import '../../features/admin/presentation/admin_members_page.dart';
import '../../features/admin/presentation/admin_orders_page.dart';
import '../../features/admin/presentation/admin_textbooks_page.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/change_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/pending_approval_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/events/presentation/events_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/campus/presentation/admin_campuses_page.dart';
import '../../features/settings/presentation/admin_settings_page.dart';
import '../../features/textbooks/presentation/my_orders_page.dart';
import '../../features/textbooks/presentation/order_complete_page.dart';
import '../../features/textbooks/presentation/textbooks_page.dart';
import '../widgets/app_shell.dart';
import '../widgets/not_found_page.dart';
import 'auth_guard.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // 로그인 상태나 프로필이 바뀌면 가드를 다시 평가한다.
  final refresh = ValueNotifier<int>(0);
  ref.listen(currentUserIdProvider, (_, _) => refresh.value++);
  ref.listen(currentProfileProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      return authRedirect((
        signedIn: ref.read(currentUserIdProvider) != null,
        profile: ref.read(currentProfileProvider).value,
      ), state.uri);
    },
    errorBuilder: (_, _) => const NotFoundPage(),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.home),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: AppRoutes.signup, builder: (_, _) => const SignupPage()),
      GoRoute(
        path: AppRoutes.pending,
        builder: (_, _) => const PendingApprovalPage(),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (_, _) => const ChangePasswordPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          _tab(AppRoutes.home, const HomePage()),
          GoRoute(
            path: AppRoutes.textbooks,
            pageBuilder: (_, state) {
              final edit = state.uri.queryParameters['edit'];
              // 카테고리가 바뀌어도 같은 위젯(선택 수량 상태)을 유지하도록 key 는 edit 로만 정한다.
              return NoTransitionPage(
                key: state.pageKey,
                child: TextbooksPage(
                  key: ValueKey(edit),
                  editOrderId: edit,
                  categoryId: state.uri.queryParameters['category'],
                ),
              );
            },
            routes: [
              GoRoute(
                path: 'complete/:orderId',
                builder: (_, state) => OrderCompletePage(
                  orderId: state.pathParameters['orderId']!,
                  edited: state.uri.queryParameters['edited'] == '1',
                ),
              ),
            ],
          ),
          _tab(AppRoutes.myOrders, const MyOrdersPage()),
          _tab(AppRoutes.events, const EventsPage()),
          GoRoute(
            path: AppRoutes.admin,
            pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const AdminHubPage(),
            ),
            routes: [
              _tab('members', const AdminMembersPage()),
              _tab('textbooks', const AdminTextbooksPage()),
              _tab('orders', const AdminOrdersPage()),
              GoRoute(
                path: 'events',
                pageBuilder: (_, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const AdminEventsPage(),
                ),
                routes: [
                  GoRoute(
                    path: ':eventId',
                    builder: (_, state) => AdminEventDetailPage(
                      eventId: state.pathParameters['eventId']!,
                    ),
                  ),
                ],
              ),
              _tab('settings', const AdminSettingsPage()),
              _tab('campuses', const AdminCampusesPage()),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

GoRoute _tab(String path, Widget page) => GoRoute(
  path: path,
  pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: page),
);
