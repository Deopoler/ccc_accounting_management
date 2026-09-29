import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/state_views.dart';
import 'settings_providers.dart';

/// 송금 계좌 안내. [amount] 가 있으면 송금할 금액, [depositName] 이 있으면 입금자명도 보여준다.
class BankAccountCard extends ConsumerWidget {
  const BankAccountCard({
    super.key,
    this.amount,
    this.depositName,
    this.title = '송금 계좌 안내',
  });

  final int? amount;
  final String? depositName;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(bankAccountProvider);
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AsyncValueView(
          value: account,
          onRetry: () => ref.invalidate(bankAccountProvider),
          data: (a) {
            if (!a.isConfigured) {
              return Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.outline),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('송금 계좌가 아직 설정되지 않았습니다. 회계 담당자에게 문의해 주세요.'),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(title),
                if (amount != null)
                  _CopyRow(
                    label: '송금 금액',
                    value: formatWon(amount!),
                    copyText: '$amount',
                    copiedMessage: '금액을 복사했습니다.',
                    emphasize: true,
                  ),
                _CopyRow(label: '은행', value: a.bankName),
                _CopyRow(
                  label: '계좌번호',
                  value: a.accountNumber,
                  copyText: '${a.bankName} ${a.accountNumber}',
                  copiedMessage:
                      '"${a.bankName} ${a.accountNumber}"을(를) 복사했습니다.',
                ),
                if (a.holder.isNotEmpty)
                  _CopyRow(label: '예금주', value: a.holder),
                if (depositName != null && depositName!.isNotEmpty)
                  _CopyRow(
                    label: '입금자명',
                    value: depositName!,
                    copyText: depositName,
                    copiedMessage: '입금자명을 복사했습니다.',
                    emphasize: true,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    this.copyText,
    this.copiedMessage,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String? copyText;
  final String? copiedMessage;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style:
                  (emphasize
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (copyText != null)
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: copyText!));
                if (context.mounted) {
                  showSnack(context, copiedMessage ?? '복사했습니다.');
                }
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('복사'),
            )
          else
            const SizedBox(height: 40),
        ],
      ),
    );
  }
}
