import '../app_exception.dart';

void downloadTextFile(
  String filename,
  String content, {
  required String mimeType,
}) {
  throw const AppException('파일 내려받기는 웹에서만 지원합니다.');
}
