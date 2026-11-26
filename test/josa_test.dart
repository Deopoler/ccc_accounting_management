import 'package:ccc_accounting_management/core/utils/josa.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('withObject (을/를)', () {
    test('한글 받침 유무에 따라 을/를을 붙인다', () {
      expect(withObject('홍길동'), '홍길동을');
      expect(withObject('김민수'), '김민수를');
      expect(withObject('은행'), '은행을');
      expect(withObject('계좌번호'), '계좌번호를');
      expect(withObject('예금주'), '예금주를');
      expect(withObject('이 회원'), '이 회원을');
    });

    test('닫는 따옴표나 괄호 앞의 마지막 글자를 기준으로 판별한다', () {
      expect(withObject('"새생활의 시작"'), '"새생활의 시작"을');
      expect(withObject('"겨울 수련회"'), '"겨울 수련회"를');
      expect(withObject('겨울 수련회 (1차)'), '겨울 수련회 (1차)를');
      expect(withObject('교재 (개정판)'), '교재 (개정판)을');
    });

    test('아라비아 숫자는 한국어 읽기 기준으로 판별한다', () {
      expect(withObject('10'), '10을');
      expect(withObject('교재 1'), '교재 1을');
      expect(withObject('교재 2'), '교재 2를');
      expect(withObject('3'), '3을');
      expect(withObject('4'), '4를');
      expect(withObject('5'), '5를');
      expect(withObject('6'), '6을');
      expect(withObject('7'), '7을');
      expect(withObject('"카카오뱅크 3333-01-2345678"'), '"카카오뱅크 3333-01-2345678"을');
      expect(withObject('9'), '9를');
    });

    test('판별할 수 없는 끝 문자는 을(를)로 폴백한다', () {
      expect(withObject('Book A'), 'Book A을(를)');
      expect(withObject('"Test"'), '"Test"을(를)');
      expect(withObject(''), '을(를)');
    });
  });

  group('withAnd (과/와)', () {
    test('한글 받침 유무와 숫자에 따라 과/와를 붙인다', () {
      expect(withAnd('"겨울 수련회"'), '"겨울 수련회"와');
      expect(withAnd('"여름 모임"'), '"여름 모임"과');
      expect(withAnd('"수련회 1"'), '"수련회 1"과');
      expect(withAnd('"수련회 2"'), '"수련회 2"와');
      expect(withAnd('"Event B"'), '"Event B"과(와)');
    });
  });
}
