/// 피드백 한 건. (Flutter 의 Feedback 위젯과 이름이 겹치지 않게 Entry 로 부른다)
class FeedbackEntry {
  const FeedbackEntry({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.senderName = '',
    this.senderStudentId = '',
    this.campusName = '',
  });

  factory FeedbackEntry.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final campus = json['campuses'] as Map<String, dynamic>?;
    return FeedbackEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: switch (json['resolved_at']) {
        final String t => DateTime.parse(t),
        _ => null,
      },
      resolvedBy: json['resolved_by'] as String?,
      senderName: profile?['name'] as String? ?? '',
      senderStudentId: profile?['student_id'] as String? ?? '',
      campusName: campus?['name'] as String? ?? '',
    );
  }

  /// 피드백 내용의 최대 길이. (서버 제약과 같다)
  static const maxLength = 2000;

  final String id;
  final String userId;
  final String content;
  final DateTime createdAt;

  /// 총괄 관리자가 확인한 시각. null 이면 미확인.
  final DateTime? resolvedAt;
  final String? resolvedBy;

  final String senderName;
  final String senderStudentId;

  /// 보낼 당시 회원의 캠퍼스 이름.
  final String campusName;

  bool get isResolved => resolvedAt != null;
}
