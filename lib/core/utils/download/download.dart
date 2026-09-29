import 'download_stub.dart'
    if (dart.library.js_interop) 'download_web.dart'
    as impl;

/// 텍스트 파일을 사용자 기기로 내려받는다. (웹 전용)
void downloadTextFile(
  String filename,
  String content, {
  String mimeType = 'text/csv;charset=utf-8',
}) => impl.downloadTextFile(filename, content, mimeType: mimeType);
