class Textbook {
  const Textbook({
    required this.id,
    required this.title,
    required this.price,
    required this.isActive,
    required this.createdAt,
  });

  factory Textbook.fromJson(Map<String, dynamic> json) => Textbook(
    id: json['id'] as String,
    title: json['title'] as String,
    price: json['price'] as int,
    isActive: json['is_active'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String title;
  final int price;
  final bool isActive;
  final DateTime createdAt;
}

/// 교재 추가/수정 폼 입력값.
class TextbookInput {
  const TextbookInput({
    required this.title,
    required this.price,
    required this.isActive,
  });

  final String title;
  final int price;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'title': title,
    'price': price,
    'is_active': isActive,
  };
}
