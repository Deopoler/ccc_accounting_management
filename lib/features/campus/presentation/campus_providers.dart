import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/campus_repository.dart';
import '../domain/campus.dart';

final campusRepositoryProvider = Provider<CampusRepository>(
  (ref) => CampusRepository(ref.watch(supabaseProvider)),
);

final campusesProvider = FutureProvider.autoDispose<List<Campus>>(
  (ref) => ref.watch(campusRepositoryProvider).listCampuses(),
);

/// 총괄 관리자가 고른 캠퍼스 id. null 이면 본인 캠퍼스.
final centralCampusOverrideProvider =
    NotifierProvider<CentralCampusOverride, String?>(CentralCampusOverride.new);

class CentralCampusOverride extends Notifier<String?> {
  @override
  String? build() {
    // 로그아웃 / 다른 계정으로 로그인하면 본인 캠퍼스로 돌아간다.
    ref.watch(currentUserIdProvider);
    return null;
  }

  void select(String? campusId) => state = campusId;
}

/// 본인 캠퍼스 id. 회원 화면(교재 신청, 이벤트, 입금 안내)은 항상 이것을 쓴다. 로그아웃 상태면 null.
final myCampusIdProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  return profile?.campusId;
});

/// 관리자 화면에서 다루는 캠퍼스 id. 로그아웃 상태면 null.
///
/// 캠퍼스 관리자는 본인 캠퍼스(서버 RLS 도 그것만 허용한다).
/// 총괄 관리자는 고른 캠퍼스(기본 본인). 모든 캠퍼스를 볼 수 있으므로, 목록이 섞이지 않게 모든 조회를 이 캠퍼스로 거른다.
final adminCampusIdProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return null;
  final override = ref.watch(centralCampusOverrideProvider);
  return profile.isCentralAdmin && override != null
      ? override
      : profile.campusId;
});

/// 회원 화면 / 관리자 화면 중 어느 쪽 캠퍼스 기준인지. (총괄 관리자가 캠퍼스를 바꾸면 관리자 화면만 바뀐다)
enum CampusScope { member, admin }

final campusIdProvider = FutureProvider.family<String?, CampusScope>(
  (ref, scope) => ref.watch(
    (scope == CampusScope.member ? myCampusIdProvider : adminCampusIdProvider)
        .future,
  ),
);

extension AdminCampusRef on WidgetRef {
  /// 관리자 화면에서 새 교재 / 카테고리 / 이벤트를 만들거나 계좌를 저장할 캠퍼스. 없으면 오류.
  Future<String> requireAdminCampusId() async {
    final id = await read(adminCampusIdProvider.future);
    if (id == null || id.isEmpty) {
      throw const AppException('캠퍼스 정보를 불러오지 못했습니다. 다시 로그인해 주세요.');
    }
    return id;
  }
}

const _lastCampusKey = 'last_campus_code';

/// 이 브라우저에서 마지막으로 로그인 / 가입한 캠퍼스 코드. 없거나 읽을 수 없으면 null.
Future<String?> loadLastCampusCode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastCampusKey);
  } catch (_) {
    return null;
  }
}

Future<void> saveLastCampusCode(String code) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCampusKey, code);
  } catch (_) {
    // 저장에 실패하면 다음에 다시 고르면 된다.
  }
}

/// 처음 선택할 캠퍼스: 마지막으로 쓴 캠퍼스, 캠퍼스가 하나뿐이면 그 캠퍼스, 아니면 null(직접 선택).
Campus? initialCampus(List<Campus> campuses, String? lastCode) {
  for (final c in campuses) {
    if (c.code == lastCode) return c;
  }
  return campuses.length == 1 ? campuses.single : null;
}
