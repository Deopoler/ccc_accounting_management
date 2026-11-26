import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

bool _cleanedOldCaches = false;

/// TrueType(0x00010000) 또는 OpenType CFF('OTTO') 머리글로 시작하는지.
bool isTrueTypeData(ByteData data) {
  if (data.lengthInBytes < 12) return false;
  final tag = data.getUint32(0);
  return tag == 0x00010000 || tag == 0x4F54544F;
}

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
        final data = (await cached.arrayBuffer().toDart).toDart.asByteData();
        if (isTrueTypeData(data)) return data;
        // 폰트가 아닌 응답(예: SPA 대체 페이지 HTML)이 저장돼 있으면 지우고 다시 받는다.
        await cache.delete(url.toJS).toDart;
      }

      final response = await web.window.fetch(url.toJS).toDart;
      if (!response.ok) {
        throw StateError('확장 폰트 응답 오류 (${response.status}): $url');
      }
      final data = (await response.arrayBuffer().toDart).toDart.asByteData();
      if (!isTrueTypeData(data)) {
        throw StateError('확장 폰트가 아닌 응답: $url');
      }
      // 캐시 쓰기는 기다리지 않는다. 사설 브라우징·용량 초과로 실패해도 내려받은 폰트는 바로 쓴다.
      unawaited(
        cache
            .put(url.toJS, web.Response(data.buffer.toJS))
            .toDart
            .then((_) {}, onError: (_) {}),
      );
      return data;
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
