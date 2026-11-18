import 'package:ccc_accounting_management/core/utils/korean_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchesKoreanQuery', () {
    test('초성 전체 및 연속 부분 문자열 매칭', () {
      expect(matchesKoreanQuery('홍길동', 'ㅎㄱㄷ'), isTrue);
      expect(matchesKoreanQuery('홍길동', 'ㄱㄷ'), isTrue);
      expect(matchesKoreanQuery('홍길동', 'ㅎㄷ'), isFalse);
    });

    test('완성형 음절과 초성 혼합 검색', () {
      expect(matchesKoreanQuery('홍길동', '홍ㄱ'), isTrue);
      expect(matchesKoreanQuery('홍길동', '길동'), isTrue);
    });

    test('쌍자음 초성 구분', () {
      expect(matchesKoreanQuery('김꽃님', 'ㄲ'), isTrue);
      expect(matchesKoreanQuery('꽃', 'ㄱ'), isFalse);
    });

    test('공백 무시(초성 경로)', () {
      expect(matchesKoreanQuery('홍 길동', 'ㅎ ㄱ'), isTrue);
    });

    test('영문 및 학번 대소문자 무시 부분 일치', () {
      expect(matchesKoreanQuery('John Doe', 'john'), isTrue);
      expect(matchesKoreanQuery('John Doe', 'DOE'), isTrue);
      expect(matchesKoreanQuery('20240001', '2024'), isTrue);
      expect(matchesKoreanQuery('20240001', '9999'), isFalse);
    });

    test('빈 검색어는 항상 참', () {
      expect(matchesKoreanQuery('홍길동', ''), isTrue);
      expect(matchesKoreanQuery('홍길동', '   '), isTrue);
    });
  });
}
