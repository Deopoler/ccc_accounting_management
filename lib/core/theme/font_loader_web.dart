import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

bool _cleanedOldCaches = false;

/// 웹에서는 CacheStorage([cacheName])를 우선 조회하고, 없거나 실패하면 네트워크/번들로 내려받는다.
Future<ByteData> loadExtendedFontAsset(
  String assetKey, {
  required String cacheName,
  required String cachePrefix,
}) async {
  if (web.window.has('caches')) {
    try {
      final caches = web.window.caches;
      if (!_cleanedOldCaches) {
        _cleanedOldCaches = true;
        unawaited(_cleanupOldCaches(caches, cachePrefix, cacheName));
      }
      final url = ui_web.assetManager.getAssetUrl(assetKey);
      final cache = await caches.open(cacheName).toDart;
      final cached = await cache.match(url.toJS).toDart;
      if (cached != null && cached.ok) {
        final buffer = await cached.arrayBuffer().toDart;
        return buffer.toDart.asByteData();
      }

      final response = await web.window.fetch(url.toJS).toDart;
      if (!response.ok) {
        throw StateError('확장 폰트 응답 오류 (${response.status}): $url');
      }
      try {
        await cache.put(url.toJS, response.clone()).toDart;
      } catch (_) {
        // 사설 브라우징·용량 초과 등으로 캐시 쓰기만 실패해도 내려받은 폰트는 바로 사용한다.
      }
      final buffer = await response.arrayBuffer().toDart;
      return buffer.toDart.asByteData();
    } catch (_) {
      // CacheStorage 접근 제한 시 일반 자산 로드로 조용히 폴백한다.
    }
  }
  return rootBundle.load(assetKey);
}

Future<void> _cleanupOldCaches(
  web.CacheStorage caches,
  String cachePrefix,
  String currentCacheName,
) async {
  try {
    final keys = (await caches.keys().toDart).toDart;
    for (final key in keys) {
      final name = key.toDart;
      if (name.startsWith(cachePrefix) && name != currentCacheName) {
        await caches.delete(name).toDart;
      }
    }
  } catch (_) {
    // 오래된 캐시 정리는 다음 방문에 다시 시도한다.
  }
}
