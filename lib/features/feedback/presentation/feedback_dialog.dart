import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/error_message.dart';
import '../../../core/widgets/feedback.dart';
import '../domain/feedback_entry.dart';
import 'feedback_providers.dart';

/// 피드백 보내기 창. 보냈으면 안내 메시지를 보여 준다.
Future<void> showFeedbackDialog(BuildContext context) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => const FeedbackDialog(),
  );
  if (sent == true && context.mounted) {
    showSnack(context, '피드백을 보냈습니다. 감사합니다.');
  }
}

/// 로그인한 회원이 운영진에게 의견을 보내는 창. 내용은 총괄 관리자만 볼 수 있다.
class FeedbackDialog extends ConsumerStatefulWidget {
  const FeedbackDialog({super.key});

  @override
  ConsumerState<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<FeedbackDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend => !_busy && _controller.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(feedbackRepositoryProvider).submit(_controller.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // 입력한 내용은 그대로 두고 이유만 보여 준다. (너무 자주 보낸 경우 등)
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('피드백 보내기'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '앱을 쓰면서 불편했던 점이나 바라는 점을 남겨 주세요. '
                '총괄 관리자만 볼 수 있습니다.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_busy,
                minLines: 5,
                maxLines: 10,
                maxLength: FeedbackEntry.maxLength,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: '내용',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _canSend ? _send : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('보내기'),
        ),
      ],
    );
  }
}
