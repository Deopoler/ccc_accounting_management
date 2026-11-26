import 'package:flutter/services.dart';

/// 비웹 / 테스트 환경에서는 번들 에셋에서 직접 읽는다.
Future<ByteData> loadExtendedFontAsset(
  String assetKey, {
  required String cacheName,
  required String cachePrefix,
}) => rootBundle.load(assetKey);
