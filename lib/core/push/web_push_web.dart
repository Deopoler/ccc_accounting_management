import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_push.dart';

// web/push/sw.js. 경로는 <base href> 기준이다.
// Flutter 서비스 워커(앱 경로, 스스로 해제됨)와 겹치지 않게 하위 scope 를 쓴다.
const _workerUrl = 'push/sw.js';
const _scope = 'push/';

bool get _hasWorkers => web.window.navigator.has('serviceWorker');

bool get _isIos {
  final nav = web.window.navigator;
  final ua = nav.userAgent;
  // iPadOS 는 데스크톱 Safari 처럼 보인다.
  return RegExp('iPhone|iPad|iPod').hasMatch(ua) ||
      (ua.contains('Macintosh') && nav.maxTouchPoints > 1);
}

bool get _isStandalone =>
    web.window.matchMedia('(display-mode: standalone)').matches;

PushSupport pushSupport() {
  final ok =
      _hasWorkers &&
      globalContext.has('PushManager') &&
      globalContext.has('Notification');
  if (ok) return PushSupport.available;
  return _isIos && !_isStandalone
      ? PushSupport.needsInstall
      : PushSupport.unsupported;
}

bool isNotificationDenied() =>
    globalContext.has('Notification') &&
    web.Notification.permission == 'denied';

Future<bool> requestNotificationPermission() async {
  if (!globalContext.has('Notification')) return false;
  if (web.Notification.permission == 'granted') return true;
  final result = await web.Notification.requestPermission().toDart;
  return result.toDart == 'granted';
}

Future<web.ServiceWorkerRegistration?> _existingRegistration() async {
  if (!_hasWorkers) return null;
  return web.window.navigator.serviceWorker.getRegistration(_scope).toDart;
}

/// 등록하고 활성화될 때까지 기다린다.
///
/// 앱 화면은 이 워커의 scope 밖이라 `serviceWorker.ready` 가 끝나지 않는다. 직접 확인한다.
Future<web.ServiceWorkerRegistration> _activeRegistration() async {
  final reg = await web.window.navigator.serviceWorker
      .register(_workerUrl.toJS, web.RegistrationOptions(scope: _scope))
      .toDart;
  for (var i = 0; reg.active == null && i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (reg.active == null) {
    throw StateError('알림 서비스 워커를 시작하지 못했습니다.');
  }
  return reg;
}

String _b64(JSArrayBuffer? buffer) =>
    base64Url.encode(buffer!.toDart.asUint8List()).replaceAll('=', '');

DevicePushSubscription _toDevice(web.PushSubscription s) =>
    DevicePushSubscription(
      endpoint: s.endpoint,
      p256dh: _b64(s.getKey('p256dh')),
      auth: _b64(s.getKey('auth')),
    );

Future<DevicePushSubscription?> currentPushSubscription() async {
  final reg = await _existingRegistration();
  if (reg == null) return null;
  final sub = await reg.pushManager.getSubscription().toDart;
  return sub == null ? null : _toDevice(sub);
}

Future<DevicePushSubscription> subscribePush(String vapidPublicKey) async {
  final reg = await _activeRegistration();
  final key = Uint8List.fromList(
    base64Url.decode(base64Url.normalize(vapidPublicKey)),
  );
  // 서버 키가 바뀌었으면 기존 구독으로는 받을 수 없으므로 새로 만든다.
  final old = await reg.pushManager.getSubscription().toDart;
  final oldKey = old?.options.applicationServerKey?.toDart.asUint8List();
  if (old != null && (oldKey == null || !_sameBytes(oldKey, key))) {
    await old.unsubscribe().toDart;
  }
  final sub = await reg.pushManager
      .subscribe(
        web.PushSubscriptionOptionsInit(
          userVisibleOnly: true,
          applicationServerKey: key.toJS,
        ),
      )
      .toDart;
  return _toDevice(sub);
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> unsubscribePush() async {
  final reg = await _existingRegistration();
  final sub = await reg?.pushManager.getSubscription().toDart;
  await sub?.unsubscribe().toDart;
}

void listenPushOpenPath(void Function(String path) onPath) {
  if (!_hasWorkers) return;
  final container = web.window.navigator.serviceWorker;
  container.addEventListener(
    'message',
    (web.MessageEvent e) {
      final data = e.data.dartify();
      if (data is Map && data['type'] == 'ccc-push-open') {
        final path = data['path'];
        if (path is String && path.startsWith('/')) onPath(path);
      }
    }.toJS,
  );
  // 이 창을 제어하지 않는 워커가 보낸 메시지도 받는다.
  container.startMessages();
}
