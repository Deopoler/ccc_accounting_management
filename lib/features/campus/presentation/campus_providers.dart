import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/riverpod/cache_for.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/campus_repository.dart';
import '../domain/campus.dart';

final campusRepositoryProvider = Provider<CampusRepository>(
  (ref) => CampusRepository(ref.watch(supabaseProvider)),
);

final campusesProvider = FutureProvider.autoDispose<List<Campus>>((ref) {
  ref.cacheFor(defaultCacheDuration, userScoped: false);
  return ref.watch(campusRepositoryProvider).listCampuses();
});

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

const missingCampusMessage = '캠퍼스 정보가 없습니다. 관리자에게 문의해 주세요.';

String? _nonEmptyCampus(String? id) => (id == null || id.isEmpty) ? null : id;

/// [campusId] 가 비어 있고 프로필 로딩이 끝났을 때 에러/빈 상태 화면을 반환한다.
/// 로딩 중이거나 캠퍼스 id 가 있으면 null 을 반환해 각 화면이 스켈레톤/데이터를 그리게 한다.
Widget? missingCampusFallback(WidgetRef ref, String? campusId) {
  if (campusId != null) return null;
  final profile = ref.watch(currentProfileProvider);
  if (profile.hasError && !profile.isLoading) {
    return ErrorView(
      error: profile.error!,
      onRetry: () => ref.invalidate(currentProfileProvider),
    );
  }
  if (profile.isLoading) return null;
  return const EmptyView(message: missingCampusMessage);
}

/// 본인 캠퍼스 id. 회원 화면(교재 신청, 이벤트, 입금 안내)은 항상 이것을 쓴다. 로그아웃 상태면 null.
final myCampusIdProvider = Provider<String?>((ref) {
  final profile = ref.watch(currentProfileProvider);
  final p = profile.hasUsableValue ? profile.requireValue : null;
  return _nonEmptyCampus(p?.campusId);
});

/// 본인 캠퍼스 (없으면 null). 내 정보 메뉴 표시용.
final myCampusProvider = FutureProvider.autoDispose<Campus?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final id = ref.watch(myCampusIdProvider);
  if (userId == null || id == null) return null;
  ref.cacheFor(defaultCacheDuration, campusScope: CampusScope.member);
  final list = await ref.watch(campusesProvider.future);
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

/// 관리자 화면에서 다루는 캠퍼스 id. 로그아웃 상태면 null.
///
/// 캠퍼스 관리자는 본인 캠퍼스(서버 RLS 도 그것만 허용한다).
/// 총괄 관리자는 고른 캠퍼스(기본 본인). 모든 캠퍼스를 볼 수 있으므로, 목록이 섞이지 않게 모든 조회를 이 캠퍼스로 거른다.
final adminCampusIdProvider = Provider<String?>((ref) {
  final profileAsync = ref.watch(currentProfileProvider);
  final profile = profileAsync.hasUsableValue ? profileAsync.requireValue : null;
  if (profile == null) return null;
  final override = ref.watch(centralCampusOverrideProvider);
  return _nonEmptyCampus(
    profile.isCentralAdmin && override != null ? override : profile.campusId,
  );
});

/// 회원 화면 / 관리자 화면 중 어느 쪽 캠퍼스 기준인지. (총괄 관리자가 캠퍼스를 바꾸면 관리자 화면만 바뀐다)
enum CampusScope { member, admin }

final campusIdProvider = Provider.family<String?, CampusScope>(
  (ref, scope) => ref.watch(
    scope == CampusScope.member ? myCampusIdProvider : adminCampusIdProvider,
  ),
);

extension AdminCampusRef on WidgetRef {
  /// 관리자 화면에서 새 교재 / 카테고리 / 이벤트를 만들거나 계좌를 저장할 캠퍼스. 없으면 오류.
  Future<String> requireAdminCampusId() async {
    if (read(currentProfileProvider).isLoading) {
      await read(currentProfileProvider.future);
    }
    final id = read(adminCampusIdProvider);
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
