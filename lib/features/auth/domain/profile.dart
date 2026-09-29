enum UserRole {
  member('회원'),
  admin('관리자');

  const UserRole(this.label);

  final String label;

  static UserRole parse(String value) =>
      value == 'admin' ? UserRole.admin : UserRole.member;
}

class Profile {
  const Profile({
    required this.id,
    required this.studentId,
    required this.name,
    required this.role,
    required this.mustChangePassword,
    required this.isApproved,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    studentId: json['student_id'] as String,
    name: json['name'] as String,
    role: UserRole.parse(json['role'] as String),
    mustChangePassword: json['must_change_password'] as bool,
    isApproved: json['is_approved'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String studentId;
  final String name;
  final UserRole role;
  final bool mustChangePassword;

  /// 관리자 가입 승인 여부. 승인 전에는 승인 대기 화면만 볼 수 있다.
  final bool isApproved;
  final DateTime createdAt;

  bool get isAdmin => role == UserRole.admin && isApproved;
}
