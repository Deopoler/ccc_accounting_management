import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/campus_repository.dart';
import '../domain/campus.dart';

final campusRepositoryProvider = Provider<CampusRepository>(
  (ref) => CampusRepository(ref.watch(supabaseProvider)),
);

final campusesProvider = FutureProvider.autoDispose<List<Campus>>(
  (ref) => ref.watch(campusRepositoryProvider).listCampuses(),
);

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
