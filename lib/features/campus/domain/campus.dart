/// 캠퍼스. 로그인 아이디(가상 이메일)의 도메인이 캠퍼스마다 다르다.
///   * KAIST: `{학번}@ccc.local`
///   * 그 외: `{학번}@{코드}.ccc.local`
class Campus {
  const Campus({
    required this.id,
    required this.code,
    required this.name,
    required this.emailDomain,
  });

  factory Campus.fromJson(Map<String, dynamic> json) => Campus(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    emailDomain: json['email_domain'] as String,
  );

  final String id;

  /// 영문 코드. 바뀌지 않는다.
  final String code;
  final String name;

  /// 로그인 이메일 도메인. 서버의 가입 트리거가 이 도메인으로 캠퍼스를 정한다.
  final String emailDomain;

  @override
  bool operator ==(Object other) => other is Campus && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
