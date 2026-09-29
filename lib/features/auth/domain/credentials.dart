/// 학번을 Supabase Auth 용 가상 이메일로 매핑할 때 쓰는 도메인.
/// Edge Function(계정 생성)과 반드시 같은 규칙을 사용해야 한다.
const studentEmailDomain = 'ccc.local';

final _studentIdPattern = RegExp(r'^[0-9A-Za-z]{4,20}$');

/// `20240001` → `20240001@ccc.local`
String studentIdToEmail(String studentId) =>
    '${studentId.trim().toLowerCase()}@$studentEmailDomain';

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
