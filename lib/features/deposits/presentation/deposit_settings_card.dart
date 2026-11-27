import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../campus/presentation/campus_providers.dart';
import '../domain/bank_deposit.dart';
import 'deposit_providers.dart';

class DepositSettingsCard extends ConsumerWidget {
  const DepositSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCampusId = ref.watch(adminCampusIdProvider);
    final settingsAsync = ref.watch(depositSettingsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AsyncValueView<CampusDepositSettings?>(
          value: activeCampusId == null
              ? const AsyncLoading<CampusDepositSettings?>()
              : settingsAsync,
          showRefreshIndicator: false,
          loading: const _DepositSettingsPlaceholder(),
          onRetry: () => ref.invalidate(depositSettingsProvider),
          isEmpty: (s) => s == null,
          empty: const EmptyView(message: '캠퍼스 정보를 불러오지 못했습니다.'),
          data: (s) => _DepositSettingsBody(
            key: ValueKey(s!.campusId),
            settings: s,
          ),
        ),
      ),
    );
  }
}

class _DepositSettingsPlaceholder extends StatelessWidget {
  const _DepositSettingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SectionTitle('자동 입금 확인')),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Switch(value: false, onChanged: null),
            ),
          ],
        ),
        Text(
          '회계 담당자 휴대폰의 은행 알림을 받아 교재 신청과 이벤트 송금을 자동으로 확인합니다.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        const SkeletonBox(height: 48, radius: 12),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(onPressed: null, child: const Text('설정 저장')),
        ),
        const Divider(height: 28),
        Text('알림 수집 주소', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        const SkeletonBox(height: 40, radius: 12),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('인증 토큰 (X-Deposit-Token)', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const SkeletonText(maxWidth: 130, fontSize: 13),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: null, child: const Text('토큰 발급')),
          ],
        ),
        const Divider(height: 28),
        Text('수신 상태', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        const SkeletonRegion(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(maxWidth: 210, fontSize: 13, announce: false),
              SizedBox(height: 4),
              SkeletonText(maxWidth: 190, fontSize: 13, announce: false),
              SizedBox(height: 4),
              SkeletonText(maxWidth: 140, fontSize: 13, announce: false),
            ],
          ),
        ),
      ],
    );
  }
}

class _DepositSettingsBody extends ConsumerStatefulWidget {
  const _DepositSettingsBody({super.key, required this.settings});

  final CampusDepositSettings settings;

  @override
  ConsumerState<_DepositSettingsBody> createState() =>
      _DepositSettingsBodyState();
}

class _DepositSettingsBodyState extends ConsumerState<_DepositSettingsBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _accountLabel = TextEditingController(
    text: widget.settings.accountLabel,
  );
  late bool _enabled = widget.settings.enabled;
  bool _saving = false;
  bool _rotating = false;
  String? _issuedToken;

  @override
  void didUpdateWidget(covariant _DepositSettingsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.campusId != widget.settings.campusId) {
      _accountLabel.text = widget.settings.accountLabel;
      _enabled = widget.settings.enabled;
      _issuedToken = null;
    } else if (oldWidget.settings.enabled != widget.settings.enabled &&
        !_saving) {
      _enabled = widget.settings.enabled;
    }
  }

  @override
  void dispose() {
    _accountLabel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(depositRepositoryProvider)
          .updateSettings(
            widget.settings.campusId,
            enabled: _enabled,
            bankCode: widget.settings.bankCode,
            accountLabel: _accountLabel.text,
          );
      ref.invalidate(depositSettingsProvider);
      if (mounted) showSnack(context, '자동 입금 확인 설정을 저장했습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rotateToken() async {
    if (_rotating) return;
    if (widget.settings.hasToken) {
      final ok = await showConfirmDialog(
        context,
        title: '토큰 재발급',
        message:
            '새 토큰을 발급하면 기존 토큰은 즉시 사용할 수 없게 됩니다.\n'
            '회계 담당자 휴대폰의 MacroDroid 설정도 새 토큰으로 바꿔야 합니다.',
        confirmLabel: '재발급',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _rotating = true);
    try {
      final token = await ref
          .read(depositRepositoryProvider)
          .rotateToken(widget.settings.campusId);
      ref.invalidate(depositSettingsProvider);
      if (mounted) {
        setState(() => _issuedToken = token);
        showSnack(context, '새 토큰을 발급했습니다. 지금 바로 복사해 주세요.');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSnack(context, '$label 복사했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final s = widget.settings;
    final ingestUrl = depositIngestUrl(Env.supabaseUrl);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle('자동 입금 확인')),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MergeSemantics(
                  child: Semantics(
                    label: '자동 입금 확인 사용',
                    child: Switch(
                      value: _enabled,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _enabled = v),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            '회계 담당자 휴대폰의 은행 알림을 받아 교재 신청과 이벤트 송금을 자동으로 확인합니다. '
            '현재 ${bankDisplayName(s.bankCode)} 알림 형식을 지원합니다.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _accountLabel,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: '계좌 별칭',
              hintText: '예) KAIST CCC',
              helperText:
                  '은행 알림에 표시되는 모임 계좌 이름입니다. 이 문구가 없는 개인 계좌 알림은 저장하지 않고 무시합니다.',
              helperMaxLines: 2,
            ),
            validator: (v) =>
                validateDepositAccountLabel(v, enabled: _enabled),
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _saving ? null : _save,
              child: const Text('설정 저장'),
            ),
          ),
          const Divider(height: 28),
          Text(
            '알림 수집 주소',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: c.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    ingestUrl.isEmpty ? '서버 주소가 설정되지 않았습니다.' : ingestUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (ingestUrl.isNotEmpty)
                  IconButton(
                    tooltip: '수집 주소 복사',
                    onPressed: () => _copy(ingestUrl, '수집 주소를'),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('인증 토큰 (X-Deposit-Token)', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    s.hasToken
                        ? '발급됨 (${s.tokenPrefix}...)'
                            '${s.tokenRotatedAt == null ? '' : ' · ${formatDateTime(s.tokenRotatedAt!)}'}'
                        : '미발급',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: _rotating ? null : _rotateToken,
                child: Text(s.hasToken ? '토큰 재발급' : '토큰 발급'),
              ),
            ],
          ),
          if (_issuedToken != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: c.primary),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '새 토큰은 지금 한 번만 표시됩니다. 화면을 닫으면 다시 볼 수 없으니 바로 복사해 주세요.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _issuedToken!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _copy(_issuedToken!, '토큰을'),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('토큰 복사'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _issuedToken = null),
                        child: const Text('확인했어요'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 28),
          Text('수신 상태', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            '마지막 수신 (연결 확인 포함): ${s.lastReceivedAt == null ? '기록 없음' : formatDateTime(s.lastReceivedAt!)}',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '마지막 알림 수신: ${s.lastDepositNotificationAt == null ? '기록 없음' : formatDateTime(s.lastDepositNotificationAt!)}',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            s.lastIgnoredAt == null
                ? '마지막 무시: 없음'
                : '마지막 무시: ${formatDateTime(s.lastIgnoredAt!)} · '
                      '${s.lastIgnoredReasonLabel} (누적 ${s.ignoredCount}건)',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
