enum UserRole {
  member('회원', 'member'),

  /// 자기 캠퍼스의 교재 / 회원 / 신청 / 이벤트 / 계좌를 관리한다.
  campusAdmin('캠퍼스 관리자', 'campus_admin'),

  /// 모든 캠퍼스를 관리하고 캠퍼스를 추가한다.
  centralAdmin('총괄 관리자', 'central_admin');

  const UserRole(this.label, this.dbValue);

  final String label;

  /// DB(profiles.role) 에 저장되는 값
  final String dbValue;

  static UserRole parse(String value) => UserRole.values.firstWhere(
    (r) => r.dbValue == value,
    orElse: () => UserRole.member,
  );
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
    this.campusId = '',
    this.deactivatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    campusId: json['campus_id'] as String? ?? '',
    studentId: json['student_id'] as String,
    name: json['name'] as String,
    role: UserRole.parse(json['role'] as String),
    mustChangePassword: json['must_change_password'] as bool,
    isApproved: json['is_approved'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    deactivatedAt: switch (json['deactivated_at']) {
      final String t => DateTime.parse(t),
      _ => null,
    },
  );

  final String id;
  final String campusId;
  final String studentId;
  final String name;
  final UserRole role;
  final bool mustChangePassword;

  /// 관리자 가입 승인 여부. 승인 전에는 승인 대기 화면만 볼 수 있다.
  final bool isApproved;
  final DateTime createdAt;

  /// 관리자가 비활성화(삭제)한 시각. null 이면 활성 상태.
  final DateTime? deactivatedAt;

  bool get isDeactivated => deactivatedAt != null;

  /// 캠퍼스 관리자 또는 총괄 관리자. 관리자 화면에 들어갈 수 있다.
  bool get isAdmin =>
      isApproved && !isDeactivated && role != UserRole.member;

  bool get isCentralAdmin =>
      isApproved && !isDeactivated && role == UserRole.centralAdmin;
}
