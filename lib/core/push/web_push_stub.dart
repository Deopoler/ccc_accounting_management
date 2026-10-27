import 'web_push.dart';

PushSupport pushSupport() => PushSupport.unsupported;

bool isNotificationDenied() => false;

Future<bool> requestNotificationPermission() async => false;

Future<DevicePushSubscription?> currentPushSubscription() async => null;

Future<DevicePushSubscription> subscribePush(String vapidPublicKey) =>
    throw UnsupportedError('웹에서만 알림을 받을 수 있습니다.');

Future<void> unsubscribePush() async {}

void listenPushOpenPath(void Function(String path) onPath) {}
