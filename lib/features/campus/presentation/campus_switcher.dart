import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/campus.dart';
import 'campus_providers.dart';

/// 관리자 화면에서 다루는 캠퍼스 (없으면 null). 제목 / 전환기 표시용.
final adminCampusProvider = FutureProvider.autoDispose<Campus?>((ref) async {
  final id = await ref.watch(adminCampusIdProvider.future);
  final list = await ref.watch(campusesProvider.future);
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

/// 총괄 관리자용 캠퍼스 전환. 관리자 화면만 바뀌고, 회원 화면(교재 신청 등)은 본인 캠퍼스 그대로다.
/// 총괄 관리자가 아니면 보이지 않는다.
class CampusSwitcher extends ConsumerWidget {
  const CampusSwitcher({super.key, this.width = 200});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCentral =
        ref.watch(currentProfileProvider).value?.isCentralAdmin ?? false;
    if (!isCentral) return const SizedBox.shrink();

    final campuses = ref.watch(campusesProvider).value ?? const <Campus>[];
    final current = ref.watch(adminCampusProvider).value;
    if (campuses.isEmpty || current == null) return const SizedBox.shrink();

    return DropdownMenu<String>(
      // 선택이 바뀌면 표시도 바뀌도록 값마다 새로 만든다.
      key: ValueKey(current.id),
      width: width,
      label: const Text('관리 중인 캠퍼스'),
      leadingIcon: Icon(Icons.school_outlined, color: context.colors.primary),
      initialSelection: current.id,
      onSelected: (id) =>
          ref.read(centralCampusOverrideProvider.notifier).select(id),
      dropdownMenuEntries: [
        for (final c in campuses) DropdownMenuEntry(value: c.id, label: c.name),
      ],
    );
  }
}
