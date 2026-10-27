import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/web_push.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/push_repository.dart';

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => PushRepository(ref.watch(supabaseProvider)),
);

/// 이 기기의 가입 신청 알림 상태.
enum SignupPushStatus {
  /// 브라우저가 지원하지 않는다.
  unsupported,

  /// iPhone / iPad 에서 홈 화면에 추가하지 않았다.
  needsInstall,

  /// 알림 권한을 거부했다. (브라우저 설정에서 허용해야 한다)
  denied,
  off,
  on,
}

final signupPushProvider =
    AsyncNotifierProvider.autoDispose<SignupPushController, SignupPushStatus>(
      SignupPushController.new,
    );

class SignupPushController extends AsyncNotifier<SignupPushStatus> {
  PushRepository get _repo => ref.read(pushRepositoryProvider);

  @override
  Future<SignupPushStatus> build() async {
    // 다른 계정으로 로그인하면 다시 확인한다. (구독은 기기마다 한 관리자에게만 있다)
    ref.watch(currentUserIdProvider);
    switch (pushSupport()) {
      case PushSupport.unsupported:
        return SignupPushStatus.unsupported;
      case PushSupport.needsInstall:
        return SignupPushStatus.needsInstall;
      case PushSupport.available:
        break;
    }
    if (isNotificationDenied()) return SignupPushStatus.denied;
    final sub = await currentPushSubscription();
    if (sub == null) return SignupPushStatus.off;
    return await _repo.isSaved(sub.endpoint)
        ? SignupPushStatus.on
        : SignupPushStatus.off;
  }

  /// 알림 받기. 사용자가 누른 직후에 호출해야 한다. (권한 요청)
  Future<void> enable() async {
    // Safari 는 누른 직후에만 권한을 물을 수 있으므로 다른 작업보다 먼저 묻는다.
    final granted = await requestNotificationPermission();
    if (!granted) {
      state = AsyncData(
        isNotificationDenied() ? SignupPushStatus.denied : SignupPushStatus.off,
      );
      throw const AppException('알림 권한을 허용해야 받을 수 있습니다.');
    }
    final key = await _repo.fetchPublicKey();
    final sub = await subscribePush(key);
    await _repo.save(sub);
    state = const AsyncData(SignupPushStatus.on);
  }

  Future<void> disable() async {
    final sub = await currentPushSubscription();
    if (sub != null) await _repo.delete(sub.endpoint);
    await unsubscribePush();
    state = const AsyncData(SignupPushStatus.off);
  }
}

/// 로그아웃 전에 이 기기의 구독을 서버에서 지운다. (로그아웃한 기기로 알림이 가지 않게)
/// 실패해도 로그아웃은 해야 하므로 오류를 무시하고 오래 기다리지 않는다.
Future<void> forgetPushDevice(PushRepository repo) async {
  try {
    await () async {
      final sub = await currentPushSubscription();
      if (sub != null) await repo.delete(sub.endpoint);
    }().timeout(const Duration(seconds: 3));
  } catch (_) {}
}
