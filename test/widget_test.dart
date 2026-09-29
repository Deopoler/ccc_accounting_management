import 'package:ccc_accounting_management/core/router/routes.dart';
import 'package:ccc_accounting_management/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatWon', () {
    test('천 단위 구분 기호와 원 단위를 붙인다', () {
      expect(formatWon(0), '0원');
      expect(formatWon(1000), '1,000원');
      expect(formatWon(1234567), '1,234,567원');
    });
  });

  group('matchDestination', () {
    test('가장 길게 일치하는 경로를 선택한다', () {
      const all = [...memberDestinations, ...adminDestinations];
      final i = matchDestination(all, '/admin/events/abc');
      expect(all[i!].path, AppRoutes.adminEvents);
    });

    test('일치하는 경로가 없으면 null', () {
      expect(matchDestination(memberDestinations, '/admin'), isNull);
    });
  });

  group('routeMetaFor', () {
    test('이벤트 상세는 이벤트 관리로 돌아간다', () {
      final meta = routeMetaFor('/admin/events/abc');
      expect(meta.parent, AppRoutes.adminEvents);
    });
  });
}
