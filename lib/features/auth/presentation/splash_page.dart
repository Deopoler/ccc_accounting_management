import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/state_views.dart';
import 'auth_providers.dart';

/// 로그인 직후 / 새로고침 시 프로필을 불러오는 동안 보여주는 화면.
/// 프로필을 불러오면 라우터 가드가 원래 가려던 화면으로 보낸다.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final signOut = OutlinedButton.icon(
      onPressed: () => ref.read(authRepositoryProvider).signOut(),
      icon: const Icon(Icons.logout),
      label: const Text('로그아웃'),
    );

    return Scaffold(
      body: SafeArea(
        child: profile.when(
          loading: () => const LoadingView(),
          error: (e, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ErrorView(
                error: e,
                onRetry: () => ref.invalidate(currentProfileProvider),
              ),
              signOut,
            ],
          ),
          data: (p) => p != null
              ? const LoadingView()
              : EmptyView(
                  icon: Icons.person_off_outlined,
                  message: '회원 정보가 등록되지 않은 계정입니다.\n회계 담당자에게 문의해 주세요.',
                  action: signOut,
                ),
        ),
      ),
    );
  }
}
