import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile(UserRole role, {bool approved = true}) => Profile(
  id: 'u1',
  campusId: 'kaist',
  studentId: '20240001',
  name: '홍길동',
  role: role,
  mustChangePassword: false,
  isApproved: approved,
  createdAt: DateTime(2026),
);

/// [profile] 로 로그인한 상태에서, 총괄 관리자 캠퍼스 선택을 [override] 로 두고 지금 캠퍼스를 구한다.
Future<String?> _active(Profile? profile, {String? override}) async {
  final container = ProviderContainer(
    overrides: [currentProfileProvider.overrideWith((ref) async => profile)],
  );
  addTearDown(container.dispose);
  container.read(centralCampusOverrideProvider.notifier).select(override);
  return container.read(activeCampusIdProvider.future);
}

void main() {
  test('로그아웃 상태면 캠퍼스가 없다', () async {
    expect(await _active(null), isNull);
  });

  test('회원 / 캠퍼스 관리자는 항상 본인 캠퍼스 (다른 캠퍼스를 골라도 무시)', () async {
    for (final r in [UserRole.member, UserRole.campusAdmin]) {
      expect(await _active(_profile(r)), 'kaist');
      expect(await _active(_profile(r), override: 'snu'), 'kaist');
    }
  });

  test('총괄 관리자는 기본이 본인 캠퍼스, 고르면 그 캠퍼스', () async {
    final central = _profile(UserRole.centralAdmin);
    expect(await _active(central), 'kaist');
    expect(await _active(central, override: 'snu'), 'snu');
  });

  test('승인되지 않은 총괄 관리자는 다른 캠퍼스를 고를 수 없다', () async {
    final pending = _profile(UserRole.centralAdmin, approved: false);
    expect(await _active(pending, override: 'snu'), 'kaist');
  });
}
