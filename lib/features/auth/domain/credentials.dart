final _studentIdPattern = RegExp(r'^[0-9A-Za-z]{4,20}$');

/// 학번 + 캠퍼스 이메일 도메인 → Supabase Auth 용 가상 이메일.
/// 서버 가입 트리거가 같은 규칙으로 학번 / 캠퍼스를 읽는다.
///   `20240001`, `ccc.local` → `20240001@ccc.local` (KAIST)
///   `20240001`, `snu.ccc.local` → `20240001@snu.ccc.local`
String studentIdToEmail(String studentId, String emailDomain) =>
    '${studentId.trim().toLowerCase()}@$emailDomain';

String? validateStudentId(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return '학번을 입력해 주세요.';
  if (!_studentIdPattern.hasMatch(v)) return '학번 형식이 올바르지 않습니다.';
  return null;
}

String? validateName(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return '이름을 입력해 주세요.';
  if (v.length > 50) return '이름이 너무 깁니다.';
  return null;
}

const minPasswordLength = 8;

String? validateNewPassword(String? value) {
  final v = value ?? '';
  if (v.isEmpty) return '새 비밀번호를 입력해 주세요.';
  if (v.length < minPasswordLength) {
    return '$minPasswordLength자 이상 입력해 주세요.';
  }
  if (!RegExp('[A-Za-z]').hasMatch(v) || !RegExp('[0-9]').hasMatch(v)) {
    return '영문과 숫자를 모두 포함해 주세요.';
  }
  return null;
}
