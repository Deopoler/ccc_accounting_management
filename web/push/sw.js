// 관리자 웹 푸시 알림 전용 서비스 워커. (lib/core/push/web_push_web.dart 가 scope "push/" 로 등록한다)
//
// Flutter 의 flutter_service_worker.js 는 앱 경로에 등록됐다가 스스로 해제되므로,
// 같은 scope 를 쓰면 이 워커와 푸시 구독까지 함께 지워진다. 그래서 하위 scope 를 따로 쓴다.
// 화면 캐시는 하지 않는다.

'use strict';

// 앱 루트 (= <base href>). scope 가 ".../push/" 이므로 한 단계 위.
const appRoot = new URL('../', self.registration.scope).href;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'CCC 회계', {
      body: data.body || '',
      tag: data.tag,
      icon: appRoot + 'icons/Icon-192.png',
      badge: appRoot + 'icons/Icon-192.png',
      lang: 'ko',
      // 앱 루트 기준 경로. 예) "admin/members"
      data: { path: data.url || '' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const path = (event.notification.data && event.notification.data.path) || '';
  event.waitUntil(
    (async () => {
      // 이미 열린 앱 창이 있으면 그 창에서 연다. 앱 창은 이 워커의 scope 밖이라 navigate() 를 못 쓰므로
      // 앱에 메시지로 경로를 알려 라우터가 이동하게 한다. (web_push_web.dart 의 onOpenPath)
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of windows) {
        if (client.url.startsWith(appRoot) && 'focus' in client) {
          await client.focus();
          client.postMessage({ type: 'ccc-push-open', path: '/' + path });
          return;
        }
      }
      await self.clients.openWindow(new URL(path, appRoot).href);
    })(),
  );
});
