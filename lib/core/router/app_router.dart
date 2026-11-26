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
import '../../features/deposits/presentation/admin_deposits_page.dart';
import '../../features/events/presentation/events_page.dart';
import '../../features/feedback/presentation/admin_feedback_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/campus/presentation/admin_campuses_page.dart';
import '../../features/settings/presentation/admin_settings_page.dart';
import '../../features/textbooks/presentation/my_orders_page.dart';
import '../../features/textbooks/presentation/order_complete_page.dart';
import '../../features/textbooks/presentation/textbooks_page.dart';
import '../push/web_push.dart';
import '../widgets/app_shell.dart';
import '../widgets/not_found_page.dart';
import 'auth_guard.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // 로그인 상태나 프로필이 바뀌면 가드를 다시 평가한다.
  final refresh = ValueNotifier<int>(0);
  String? signingOutUserId;
  ref.listen(currentUserIdProvider, (_, next) {
    if (next == null) signingOutUserId = null;
    refresh.value++;
  });
  ref.listen(currentProfileProvider, (_, next) {
    refresh.value++;
    final profile = next.value;
    if (profile != null &&
        profile.isDeactivated &&
        signingOutUserId != profile.id) {
      signingOutUserId = profile.id;
      ref.read(authRepositoryProvider).signOut();
    }
  });

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
              _tab('deposits', const AdminDepositsPage()),
              _tab('settings', const AdminSettingsPage()),
              _tab('campuses', const AdminCampusesPage()),
              _tab('feedback', const AdminFeedbackPage()),
            ],
          ),
        ],
      ),
    ],
  );

  // 푸시 알림(가입 신청 → 회원 관리, 새 피드백 → 피드백함 등)을 누르면 열린 앱 창에서 해당 화면으로 이동한다. (web/push/sw.js)
  var disposed = false;
  listenPushOpenPath((path) {
    if (!disposed) router.go(path);
  });

  ref.onDispose(() {
    disposed = true;
    router.dispose();
    refresh.dispose();
  });
  return router;
});

GoRoute _tab(String path, Widget page) => GoRoute(
  path: path,
  pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: page),
);
