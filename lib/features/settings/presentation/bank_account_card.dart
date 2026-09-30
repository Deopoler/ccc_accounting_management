import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/state_views.dart';
import 'settings_providers.dart';
import '../../campus/presentation/campus_providers.dart';

/// 송금 계좌 안내. [amount] 가 있으면 송금할 금액, [depositName] 이 있으면 입금자명도 보여준다.
class BankAccountCard extends ConsumerWidget {
  const BankAccountCard({
    super.key,
    this.amount,
    this.depositName,
    this.title = '송금 계좌 안내',
    this.embedded = false,
  });

  final int? amount;
  final String? depositName;
  final String title;

  /// 다른 카드(회색 면) 안에 넣을 때 true: 흰(배경색) 면으로 구분한다.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(bankAccountProvider(CampusScope.member));
    final theme = Theme.of(context);

    final c = context.colors;
    return Card(
      color: embedded ? c.background : c.surfaceMuted,
      shape: embedded
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            )
          : null,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: emphasize ? 20 : 16,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: emphasize ? -0.4 : 0,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (copyText != null)
            // 값 칸을 넓게 쓰도록 작은 글자 버튼으로 둔다.
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: copyText!));
                if (context.mounted) {
                  showSnack(context, copiedMessage ?? '복사했습니다.');
                }
              },
              child: const Text('복사'),
            )
          else
            const SizedBox(height: 36),
        ],
      ),
    );
  }
}
