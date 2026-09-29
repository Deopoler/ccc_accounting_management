import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';

/// 예외를 사용자에게 보여줄 한국어 메시지로 변환한다.
String errorMessage(Object error) {
  return switch (error) {
    AppException(:final message) => message,
    AuthException(:final message) => _authMessage(message),
    PostgrestException(:final message, :final code) => _postgrestMessage(
      message,
      code,
    ),
    FunctionException(:final details) => _functionMessage(details),
    _
        when error.toString().contains('Failed to fetch') ||
            error.toString().contains('SocketException') =>
      '서버에 연결할 수 없습니다. 네트워크 상태를 확인해 주세요.',
    _ => '알 수 없는 오류가 발생했습니다.\n$error',
  };
}

String _authMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('invalid login credentials')) {
    return '학번 또는 비밀번호가 올바르지 않습니다.';
  }
  if (lower.contains('already registered') ||
      lower.contains('already exists')) {
    return '이미 가입된 학번입니다. 로그인해 주세요.';
  }
  if (lower.contains('signups not allowed') ||
      lower.contains('signup is disabled')) {
    return '현재 가입이 막혀 있습니다. 회계 담당자에게 문의해 주세요.';
  }
  if (lower.contains('database error saving new user')) {
    return '가입 정보가 올바르지 않습니다. 학번과 이름을 확인해 주세요.';
  }
  if (lower.contains('should be different')) {
    return '새 비밀번호는 기존 비밀번호와 달라야 합니다.';
  }
  if (lower.contains('password should be at least') || lower.contains('weak')) {
    return '비밀번호가 너무 짧거나 단순합니다.';
  }
  if (lower.contains('jwt') || lower.contains('session')) {
    return '로그인이 만료되었습니다. 다시 로그인해 주세요.';
  }
  return message;
}

String _postgrestMessage(String message, String? code) {
  // 서버 함수에서 raise exception 으로 던진 한국어 메시지는 그대로 보여준다.
  if (code == 'P0001') return message;
  return switch (code) {
    '42501' => '권한이 없습니다.',
    '23505' => '이미 존재하는 항목입니다.',
    '23503' => '다른 데이터에서 사용 중이라 처리할 수 없습니다.',
    _ => message,
  };
}

String _functionMessage(Object? details) {
  if (details is Map && details['error'] is String) {
    return details['error'] as String;
  }
  return details?.toString() ?? '서버 함수 호출에 실패했습니다.';
}
