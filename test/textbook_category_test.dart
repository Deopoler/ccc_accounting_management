import 'package:ccc_accounting_management/features/textbooks/domain/textbook.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_category.dart';
import 'package:flutter_test/flutter_test.dart';

Textbook _book(String id, {String? category, int order = 0}) => Textbook(
  id: id,
  title: id,
  price: 1000,
  isActive: true,
  createdAt: DateTime(2026),
  categoryId: category,
  sortOrder: order,
);

void main() {
  const categories = [
    TextbookCategory(id: 'b', name: '나중', sortOrder: 2),
    TextbookCategory(id: 'a', name: '먼저', sortOrder: 1),
    TextbookCategory(id: 'empty', name: '빈 카테고리', sortOrder: 0),
  ];

  test('sort_order 순서로 묶고, 카테고리 없는 교재는 맨 뒤 "기타"', () {
    final groups = groupByCategory(categories, [
      _book('1', category: 'b'),
      _book('2'),
      _book('3', category: 'a'),
      _book('4', category: 'a'),
    ]);
    expect(groups.map((g) => g.name), ['먼저', '나중', uncategorizedName]);
    expect(groups.first.textbooks.map((t) => t.id), ['3', '4']);
    expect(groups.last.id, uncategorizedId);
  });

  test('회원 화면은 빈 카테고리를 빼고, 관리자 화면은 포함한다', () {
    final books = [_book('1', category: 'a')];
    expect(groupByCategory(categories, books).map((g) => g.id), ['a']);
    expect(
      groupByCategory(categories, books, includeEmpty: true).map((g) => g.id),
      ['empty', 'a', 'b'],
    );
  });

  test('삭제된(알 수 없는) 카테고리의 교재는 "기타"로 간다', () {
    final groups = groupByCategory(categories, [_book('1', category: 'gone')]);
    expect(groups.single.id, uncategorizedId);
  });

  test('카테고리 안은 교재 순서(sort_order)대로, 같으면 교재명순', () {
    final groups = groupByCategory(categories, [
      _book('다', category: 'a', order: 0),
      _book('가', category: 'a', order: 2),
      _book('나', category: 'a', order: 0),
    ]);
    expect(groups.single.textbooks.map((t) => t.id), ['나', '다', '가']);
  });

  test('수정할 때는 sort_order 를 보내지 않아 기존 순서를 유지한다', () {
    const edit = TextbookInput(title: 't', price: 1, isActive: true);
    expect(edit.toJson().containsKey('sort_order'), isFalse);
    const create = TextbookInput(
      title: 't',
      price: 1,
      isActive: true,
      sortOrder: 5,
    );
    expect(create.toJson()['sort_order'], 5);
  });

  test('TextbookInput 은 category_id 를 보낸다 (null 이면 기타)', () {
    expect(
      const TextbookInput(
        title: 't',
        price: 1,
        isActive: true,
        categoryId: 'a',
      ).toJson()['category_id'],
      'a',
    );
    expect(
      const TextbookInput(title: 't', price: 1, isActive: true).toJson(),
      containsPair('category_id', null),
    );
  });
}
