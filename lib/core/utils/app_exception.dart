/// 사용자에게 그대로 보여줄 메시지를 가진 앱 내부 예외.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}
