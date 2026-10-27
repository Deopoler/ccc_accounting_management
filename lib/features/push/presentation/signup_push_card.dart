import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import 'push_providers.dart';

/// 설정 화면: 이 기기에서 가입 신청 알림(웹 푸시) 받기.
class SignupPushCard extends ConsumerStatefulWidget {
  const SignupPushCard({super.key});

  @override
  ConsumerState<SignupPushCard> createState() => _SignupPushCardState();
}

class _SignupPushCardState extends ConsumerState<SignupPushCard> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = ref.read(signupPushProvider.notifier);
    try {
      // 권한 요청은 누른 직후여야 하므로 다른 비동기 작업 없이 바로 호출한다.
      await (on ? controller.enable() : controller.disable());
      if (mounted) {
        showSnack(
          context,
          on ? '이 기기에서 가입 신청 알림을 받습니다.' : '이 기기의 가입 신청 알림을 껐습니다.',
        );
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(signupPushProvider);
    final value = status.value;

    final hint = switch (value) {
      SignupPushStatus.unsupported =>
        '이 브라우저는 알림을 지원하지 않습니다. Chrome, Edge, Safari 최신 버전에서 열어 주세요.',
      SignupPushStatus.needsInstall =>
        'iPhone / iPad 는 Safari 공유 버튼 > "홈 화면에 추가"로 설치한 앱에서 알림을 켤 수 있습니다.',
      SignupPushStatus.denied =>
        '알림 권한이 거부되어 있습니다. 브라우저(또는 기기) 설정에서 이 사이트의 알림을 허용한 뒤 다시 열어 주세요.',
      _ => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: SectionTitle('가입 신청 알림')),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Switch(
                    value: value == SignupPushStatus.on,
                    onChanged:
                        _busy ||
                            (value != SignupPushStatus.on &&
                                value != SignupPushStatus.off)
                        ? null
                        : _toggle,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '새 가입 신청이 들어오면 이 기기로 알림을 보냅니다. '
                    '앱을 닫아 두어도 받을 수 있고, 기기(브라우저)마다 따로 켭니다.\n'
                    '캠퍼스 관리자는 자기 캠퍼스, 총괄 관리자는 모든 캠퍼스의 가입 신청을 받습니다.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                  if (status.hasError) ...[
                    const SizedBox(height: 8),
                    Text(
                      '알림 상태를 확인하지 못했습니다.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
