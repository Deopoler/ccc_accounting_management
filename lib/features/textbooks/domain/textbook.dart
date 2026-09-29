class Textbook {
  const Textbook({
    required this.id,
    required this.title,
    required this.price,
    required this.isActive,
    required this.createdAt,
    this.categoryId,
    this.sortOrder = 0,
  });

  factory Textbook.fromJson(Map<String, dynamic> json) => Textbook(
    id: json['id'] as String,
    title: json['title'] as String,
    price: json['price'] as int,
    isActive: json['is_active'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
    categoryId: json['category_id'] as String?,
    sortOrder: json['sort_order'] as int? ?? 0,
  );

  final String id;
  final String title;
  final int price;
  final bool isActive;
  final DateTime createdAt;

  /// null 이면 "기타"
  final String? categoryId;

  /// 카테고리 안에서의 표시 순서 (작을수록 위)
  final int sortOrder;
}

/// 교재 추가/수정 폼 입력값.
class TextbookInput {
  const TextbookInput({
    required this.title,
    required this.price,
    required this.isActive,
    this.categoryId,
    this.sortOrder,
  });

  final String title;
  final int price;
  final bool isActive;
  final String? categoryId;

  /// 새 교재의 순서. 수정할 때는 null 로 두어 기존 순서를 유지한다.
  final int? sortOrder;

  Map<String, dynamic> toJson() => {
    'title': title,
    'price': price,
    'is_active': isActive,
    'category_id': categoryId,
    'sort_order': ?sortOrder,
  };
}
