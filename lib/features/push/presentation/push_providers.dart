import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/push/web_push.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/push_repository.dart';

const _optedOutKey = 'push_opted_out';
const _promptAskedKey = 'push_prompt_asked';

/// 브라우저 웹 푸시 API 추상화. 테스트에서 가짜 구현을 주입할 수 있다.
class PushBrowser {
  const PushBrowser();

  PushSupport support() => pushSupport();
  bool isGranted() => isNotificationGranted();
  bool isDenied() => isNotificationDenied();
  Future<bool> requestPermission() => requestNotificationPermission();
  Future<DevicePushSubscription?> currentSubscription() =>
      currentPushSubscription();
  Future<DevicePushSubscription> subscribe(String vapidPublicKey) =>
      subscribePush(vapidPublicKey);
  Future<void> unsubscribe() => unsubscribePush();
}

final pushBrowserProvider = Provider<PushBrowser>(
  (ref) => const PushBrowser(),
);

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => PushRepository(ref.watch(supabaseProvider)),
);

/// 이 기기의 웹 푸시 알림 상태. (관리자 가입 신청 알림과 회원 교재 도착 알림이 함께 쓴다)
enum SignupPushStatus {
  /// 브라우저가 지원하지 않는다.
  unsupported,

  /// iPhone / iPad 에서 홈 화면에 추가하지 않았다.
  needsInstall,

  /// 알림 권한을 거부했다. (브라우저 설정에서 허용해야 한다)
  denied,

  /// 일반 회원의 기본 ON 상태이나 아직 브라우저 알림 권한(사용자 제스처 필요)을 받지 못한 상태.
  pendingPermission,

  off,
  on,
}

final signupPushProvider =
    AsyncNotifierProvider.autoDispose<SignupPushController, SignupPushStatus>(
      SignupPushController.new,
    );

class SignupPushController extends AsyncNotifier<SignupPushStatus> {
  PushRepository get _repo => ref.read(pushRepositoryProvider);
  PushBrowser get _browser => ref.read(pushBrowserProvider);

  bool _optedOut = false;
  bool _promptAsked = false;

  @override
  Future<SignupPushStatus> build() async {
    // 다른 계정으로 로그인하면 다시 확인한다.
    ref.watch(currentUserIdProvider);

    final browser = _browser;
    switch (browser.support()) {
      case PushSupport.unsupported:
        return SignupPushStatus.unsupported;
      case PushSupport.needsInstall:
        return SignupPushStatus.needsInstall;
      case PushSupport.available:
        break;
    }
    if (browser.isDenied()) return SignupPushStatus.denied;

    final profile = await ref.watch(currentProfileProvider.future);
    final isMember =
        profile != null &&
        profile.isApproved &&
        profile.role == UserRole.member;

    _optedOut = await _loadBool(_optedOutKey);
    _promptAsked = await _loadBool(_promptAskedKey);

    final sub = await browser.currentSubscription();
    if (sub != null && await _repo.isSaved(sub.endpoint)) {
      return SignupPushStatus.on;
    }

    // 일반 회원(member)은 교재 도착 알림이 기본 ON(opt-out)이다.
    // 브라우저 권한이 이미 허용되어 있으면 추가 탭 없이 자동으로 구독한다.
    // 관리자는 과거에 알림을 끈 기록이 별도로 없으므로 자동 구독하지 않는다.
    if (isMember && !_optedOut) {
      if (browser.isGranted()) {
        try {
          final key = await _repo.fetchPublicKey();
          final created = await browser.subscribe(key);
          await _repo.save(created);
          return SignupPushStatus.on;
        } catch (_) {
          return SignupPushStatus.off;
        }
      }
      return SignupPushStatus.pendingPermission;
    }

    return SignupPushStatus.off;
  }

  /// 알림 받기. 사용자가 누른 직후에 호출해야 한다. (권한 요청)
  Future<void> enable() async {
    // Safari 는 누른 직후에만 권한을 물을 수 있으므로 다른 작업보다 먼저 묻는다.
    final granted = await _browser.requestPermission();
    _promptAsked = true;
    await _saveBool(_promptAskedKey, true);
    if (!granted) {
      state = AsyncData(
        _browser.isDenied() ? SignupPushStatus.denied : SignupPushStatus.off,
      );
      throw const AppException('알림 권한을 허용해야 받을 수 있습니다.');
    }
    _optedOut = false;
    await _saveBool(_optedOutKey, false);
    final key = await _repo.fetchPublicKey();
    final sub = await _browser.subscribe(key);
    await _repo.save(sub);
    state = const AsyncData(SignupPushStatus.on);
  }

  Future<void> disable() async {
    _optedOut = true;
    await _saveBool(_optedOutKey, true);
    final sub = await _browser.currentSubscription();
    if (sub != null) await _repo.delete(sub.endpoint);
    await _browser.unsubscribe();
    state = const AsyncData(SignupPushStatus.off);
  }

  /// 교재 신청 시점(사용자 탭 핸들러 시작)에 아직 권한을 묻지 않았다면 묻고 구독한다.
  ///
  /// Safari / iOS 는 사용자 제스처 안에서만 Notification.requestPermission 을 허용하므로
  /// 네트워크 await 전에 동기적으로 바로 시작하고, 신청 처리는 이 작업을 기다리지 않는다.
  void enableOnOrderInGesture() {
    try {
      final profile = ref.read(currentProfileProvider).value;
      if (profile == null ||
          !profile.isApproved ||
          profile.role != UserRole.member) {
        return;
      }
      if (_optedOut || _promptAsked) return;
      final browser = _browser;
      if (browser.support() != PushSupport.available) return;
      if (browser.isDenied()) return;
      if (state.value == SignupPushStatus.on) return;

      _promptAsked = true;
      final permissionFuture = browser.isGranted()
          ? Future<bool>.value(true)
          : browser.requestPermission();

      unawaited(_finishOrderSubscribe(permissionFuture));
    } catch (_) {
      // 알림 처리 오류가 교재 신청을 막으면 안 된다.
    }
  }

  Future<void> _finishOrderSubscribe(Future<bool> permissionFuture) async {
    try {
      await _saveBool(_promptAskedKey, true);
      final granted = await permissionFuture;
      if (!granted) {
        state = AsyncData(
          _browser.isDenied()
              ? SignupPushStatus.denied
              : SignupPushStatus.pendingPermission,
        );
        return;
      }
      if (_optedOut) return;
      final key = await _repo.fetchPublicKey();
      final sub = await _browser.subscribe(key);
      await _repo.save(sub);
      state = const AsyncData(SignupPushStatus.on);
    } catch (_) {
      // 백그라운드 자동 구독 실패는 신청 흐름을 방해하지 않는다.
    }
  }
}

Future<bool> _loadBool(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> _saveBool(String key, bool value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  } catch (_) {
    // 사설 브라우징 등에서 저장에 실패해도 앱 동작은 계속된다.
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
