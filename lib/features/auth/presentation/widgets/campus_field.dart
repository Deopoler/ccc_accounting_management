import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/utils/error_message.dart';
import '../../../campus/domain/campus.dart';
import '../../../campus/presentation/campus_providers.dart';
import 'auth_card.dart';

/// 로그인 / 가입 화면의 캠퍼스 선택.
///
/// 캠퍼스가 하나뿐이면 보이지 않는다. (자동 선택은 [CampusSelection] 이 한다)
class CampusField extends ConsumerWidget {
  const CampusField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.helperText,
  });

  final Campus? value;
  final ValueChanged<Campus?> onChanged;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campuses = ref.watch(campusesProvider);
    return switch (campuses) {
      AsyncData(value: final list) when list.length <= 1 =>
        list.isEmpty
            ? const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: FormErrorText('등록된 캠퍼스가 없습니다. 회계 담당자에게 문의해 주세요.'),
              )
            : const SizedBox.shrink(),
      AsyncData(value: final list) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<Campus>(
          // 저장된 캠퍼스를 나중에 읽어 와도 선택이 바뀌도록 값마다 새로 만든다.
          key: ValueKey(value?.id),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '캠퍼스',
            prefixIcon: const Icon(Icons.school_outlined),
            helperText: helperText,
          ),
          items: [
            for (final c in list)
              DropdownMenuItem(value: c, child: Text(c.name)),
          ],
          onChanged: enabled ? onChanged : null,
          validator: (v) => v == null ? '캠퍼스를 선택해 주세요.' : null,
        ),
      ),
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Expanded(
              child: FormErrorText(
                '캠퍼스 목록을 불러오지 못했습니다. ${errorMessage(error)}',
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(campusesProvider),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(),
      ),
    };
  }
}

/// 로그인 / 가입 화면이 쓰는 캠퍼스 선택 상태.
///   사용자가 고른 캠퍼스 → 이 브라우저에서 마지막으로 쓴 캠퍼스 → 캠퍼스가 하나면 그 캠퍼스.
mixin CampusSelection<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Campus? _picked;
  String? _lastCode;

  @override
  void initState() {
    super.initState();
    loadLastCampusCode().then((code) {
      if (mounted) setState(() => _lastCode = code);
    });
  }

  /// 지금 선택된 캠퍼스. 목록을 불러오기 전이거나 골라야 하면 null.
  /// build 에서는 `ref.watch(campusesProvider)` 로 목록 변화를 구독한다.
  Campus? get campus {
    if (_picked != null) return _picked;
    final list = ref.read(campusesProvider).value;
    return list == null ? null : initialCampus(list, _lastCode);
  }

  void pickCampus(Campus? c) => setState(() => _picked = c);
}
