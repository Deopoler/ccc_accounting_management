import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_theme.dart';
import 'font_loader_stub.dart'
    if (dart.library.js_interop) 'font_loader_web.dart'
    as impl;

/// 확장 폰트 CacheStorage 접두사와 현재 캐시 버전.
///
/// 폰트를 재생성하면 이 버전을 올려 이전 캐시가 정리되게 한다.
const extFontCachePrefix = 'pretendard-ext-';
const extFontCacheName = '${extFontCachePrefix}v1';

const _extFontAssets = [
  'assets/fonts/PretendardExt-Regular.ttf',
  'assets/fonts/PretendardExt-Bold.ttf',
];

/// 첫 프레임이 그려진 뒤 확장 한글 폰트를 백그라운드에서 내려받아 등록한다.
void scheduleExtendedFontsLoad() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(loadExtendedFonts());
  });
}

/// KS X 1001 외 현대 한글 음절(8,822자) 폰트를 [AppTheme.extFontFamily] 로 등록한다.
///
/// 등록이 끝나면 [FontLoader.load] 가 `fontsChange` 시스템 메시지를 보내고,
/// [RenderParagraph] 와 [RenderEditable] 이 [RelayoutWhenSystemFontsChangeMixin] 으로
/// 이미 화면에 나온 글자까지 자동으로 다시 배치한다.
Future<void> loadExtendedFonts({
  @visibleForTesting FontLoader Function(String family)? createFontLoader,
  @visibleForTesting Future<ByteData> Function(String key)? loadAsset,
}) async {
  final load =
      loadAsset ??
      (String key) => impl.loadExtendedFontAsset(
        key,
        cacheName: extFontCacheName,
        cachePrefix: extFontCachePrefix,
      );
  final loader = (createFontLoader ?? FontLoader.new)(AppTheme.extFontFamily);
  try {
    // 두 굵기를 병렬로 내려받고 한 번에 등록해 재레이아웃 알림이 겹치지 않게 한다.
    final bytesList = await Future.wait([
      for (final path in _extFontAssets) load(path),
    ]);
    for (final bytes in bytesList) {
      loader.addFont(Future<ByteData>.value(bytes));
    }
    await loader.load();
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('확장 폰트 로드 실패 (기본 폰트로 계속 동작): $error\n$stackTrace');
    }
  }
}
