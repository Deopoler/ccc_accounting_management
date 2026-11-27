import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/josa.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import 'settings_providers.dart';
import '../domain/bank_account.dart';
import '../../campus/presentation/campus_providers.dart';

/// 송금 계좌 안내. [amount] 가 있으면 송금할 금액, [depositName] 이 있으면 입금자명도 보여준다.
class BankAccountCard extends ConsumerWidget {
  const BankAccountCard({
    super.key,
    this.amount,
    this.expectAmount = false,
    this.depositName,
    this.title = '송금 계좌 안내',
    this.embedded = false,
  });

  final int? amount;
  final bool expectAmount;
  final String? depositName;
  final String title;

  /// 다른 카드(회색 면) 안에 넣을 때 true: 흰(배경색) 면으로 구분한다.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campusId = ref.watch(myCampusIdProvider);
    final account = ref.watch(bankAccountProvider(CampusScope.member));
    final theme = Theme.of(context);
    final showDepositName = depositName != null && depositName!.isNotEmpty;

    final campusFallback = missingCampusFallback(ref, campusId);

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
        child: campusFallback ??
            AsyncValueView(
          value: campusId == null ? const AsyncLoading<BankAccount>() : account,
          showRefreshIndicator: false,
          onRetry: () => ref.invalidate(bankAccountProvider),
          loading: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(title),
              if (amount != null)
                _CopyRow(
                  label: '송금 금액',
                  value: formatWon(amount!),
                  emphasize: true,
                )
              else if (expectAmount)
                const _SkeletonInfoRow(label: '송금 금액', width: 110, fontSize: 20),
              const _SkeletonInfoRow(label: '은행', width: 90),
              const _SkeletonInfoRow(label: '계좌번호', width: 150),
              const _SkeletonInfoRow(label: '예금주', width: 80),
              if (showDepositName)
                const _SkeletonInfoRow(label: '입금자명', width: 110),
            ],
          ),
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
                  )
                else if (expectAmount)
                  const _SkeletonInfoRow(label: '송금 금액', width: 110, fontSize: 20),
                _CopyRow(label: '은행', value: a.bankName),
                _CopyRow(
                  label: '계좌번호',
                  value: a.accountNumber,
                  copyText: '${a.bankName} ${a.accountNumber}',
                  copiedMessage:
                      '${withObject('"${a.bankName} ${a.accountNumber}"')} 복사했습니다.',
                ),
                if (a.holder.isNotEmpty)
                  _CopyRow(label: '예금주', value: a.holder),
                if (showDepositName)
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
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontFamilyFallback: AppTheme.fontFamilyFallback,
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
            const SizedBox(height: 44),
        ],
      ),
    );
  }
}

class _SkeletonInfoRow extends StatelessWidget {
  const _SkeletonInfoRow({
    required this.label,
    required this.width,
    this.fontSize = 16,
  });

  final String label;
  final double width;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 44,
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
              child: SkeletonText(maxWidth: width, fontSize: fontSize),
            ),
          ],
        ),
      ),
    );
  }
}
