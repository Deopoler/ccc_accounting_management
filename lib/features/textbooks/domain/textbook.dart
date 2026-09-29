class Textbook {
  const Textbook({
    required this.id,
    required this.title,
    required this.price,
    required this.isActive,
    required this.createdAt,
    this.categoryId,
  });

  factory Textbook.fromJson(Map<String, dynamic> json) => Textbook(
    id: json['id'] as String,
    title: json['title'] as String,
    price: json['price'] as int,
    isActive: json['is_active'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
    categoryId: json['category_id'] as String?,
  );

  final String id;
  final String title;
  final int price;
  final bool isActive;
  final DateTime createdAt;

  /// null 이면 "기타"
  final String? categoryId;
}

/// 교재 추가/수정 폼 입력값.
class TextbookInput {
  const TextbookInput({
    required this.title,
    required this.price,
    required this.isActive,
    this.categoryId,
  });

  final String title;
  final int price;
  final bool isActive;
  final String? categoryId;

  Map<String, dynamic> toJson() => {
    'title': title,
    'price': price,
    'is_active': isActive,
    'category_id': categoryId,
  };
}
