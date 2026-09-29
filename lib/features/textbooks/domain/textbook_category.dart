import 'textbook.dart';

class TextbookCategory {
  const TextbookCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory TextbookCategory.fromJson(Map<String, dynamic> json) =>
      TextbookCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        sortOrder: json['sort_order'] as int,
      );

  final String id;
  final String name;
  final int sortOrder;
}

/// 카테고리가 없는 교재를 모은 가상 카테고리 id.
const uncategorizedId = '_uncategorized';
const uncategorizedName = '기타';

/// 카테고리와 그 안의 교재.
class CategoryGroup {
  const CategoryGroup({required this.category, required this.textbooks});

  /// null 이면 "기타" (카테고리 없음)
  final TextbookCategory? category;
  final List<Textbook> textbooks;

  String get id => category?.id ?? uncategorizedId;
  String get name => category?.name ?? uncategorizedName;
}

/// 카테고리 순서(sort_order, 이름)대로 교재를 묶는다. "기타"는 교재가 있을 때만 맨 뒤에 붙는다.
///
/// [includeEmpty] 가 false 면 교재가 없는 카테고리는 뺀다. (회원 화면)
List<CategoryGroup> groupByCategory(
  List<TextbookCategory> categories,
  Iterable<Textbook> textbooks, {
  bool includeEmpty = false,
}) {
  final known = {for (final c in categories) c.id};
  final byCategory = <String, List<Textbook>>{};
  for (final t in textbooks) {
    final key = (t.categoryId != null && known.contains(t.categoryId))
        ? t.categoryId!
        : uncategorizedId;
    byCategory.putIfAbsent(key, () => []).add(t);
  }

  final sorted = [...categories]
    ..sort((a, b) {
      final o = a.sortOrder.compareTo(b.sortOrder);
      return o != 0 ? o : a.name.compareTo(b.name);
    });

  return [
    for (final c in sorted)
      if (includeEmpty || (byCategory[c.id]?.isNotEmpty ?? false))
        CategoryGroup(category: c, textbooks: byCategory[c.id] ?? const []),
    if (byCategory[uncategorizedId]?.isNotEmpty ?? false)
      CategoryGroup(category: null, textbooks: byCategory[uncategorizedId]!),
  ];
}
