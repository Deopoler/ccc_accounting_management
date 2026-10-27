import 'web_push_stub.dart'
    if (dart.library.js_interop) 'web_push_web.dart'
    as impl;

/// 이 기기(브라우저)에서 웹 푸시를 받을 수 있는지.
enum PushSupport {
  /// 브라우저가 웹 푸시를 지원하지 않는다.
  unsupported,

  /// iPhone / iPad: 홈 화면에 추가한 앱에서만 받을 수 있다.
  needsInstall,

  available,
}

/// 브라우저 푸시 구독. 서버(push_subscriptions)에 저장해 Edge Function 이 이 주소로 보낸다.
class DevicePushSubscription {
  const DevicePushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;

  /// 암호화 공개 키 / 인증 secret (base64url)
  final String p256dh;
  final String auth;
}

PushSupport pushSupport() => impl.pushSupport();

/// 알림 권한을 이미 거부했는지. (브라우저 설정에서만 다시 허용할 수 있다)
bool isNotificationDenied() => impl.isNotificationDenied();

/// 알림 권한을 묻는다. 허용하면 true.
///
/// Safari 는 사용자가 누른 직후에만 물을 수 있으므로, 다른 비동기 작업보다 먼저 호출한다.
Future<bool> requestNotificationPermission() =>
    impl.requestNotificationPermission();

/// 이 기기의 현재 구독. 없으면 null.
Future<DevicePushSubscription?> currentPushSubscription() =>
    impl.currentPushSubscription();

/// 푸시 전용 서비스 워커를 등록하고 구독한다. [vapidPublicKey] 는 base64url.
Future<DevicePushSubscription> subscribePush(String vapidPublicKey) =>
    impl.subscribePush(vapidPublicKey);

Future<void> unsubscribePush() => impl.unsubscribePush();

/// 알림을 눌렀을 때 이미 열린 앱 창에서 [onPath] 로 이동한다. (예: `/admin/members`)
void listenPushOpenPath(void Function(String path) onPath) =>
    impl.listenPushOpenPath(onPath);
