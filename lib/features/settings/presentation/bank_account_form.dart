import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/josa.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../campus/presentation/campus_providers.dart';
import '../domain/bank_account.dart';
import 'settings_providers.dart';

/// 캠퍼스 송금 계좌 설정 섹션.
class BankAccountSection extends ConsumerWidget {
  const BankAccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCampusId = ref.watch(adminCampusIdProvider);
    final account = ref.watch(bankAccountProvider(CampusScope.admin));

    return AsyncValueView<BankAccount>(
      value: activeCampusId == null
          ? const AsyncLoading<BankAccount>()
          : account,
      showRefreshIndicator: false,
      loading: const BankAccountFormPlaceholder(),
      onRetry: () => ref.invalidate(bankAccountProvider),
      // 캠퍼스가 바뀌면 입력 중이던 값을 버리고 새 캠퍼스 계좌로 폼을 새로 만든다.
      data: (a) => BankAccountForm(key: ValueKey(activeCampusId), initial: a),
    );
  }
}

class BankAccountFormPlaceholder extends StatelessWidget {
  const BankAccountFormPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('송금 계좌'),
          Text(
            '교재 신청 완료 화면과 이벤트 화면에서 회원에게 안내됩니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const SkeletonRegion(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonBox(height: 48, radius: 12, announce: false),
                SizedBox(height: 16),
                SkeletonBox(height: 48, radius: 12, announce: false),
                SizedBox(height: 16),
                SkeletonBox(height: 48, radius: 12, announce: false),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: null, child: const Text('저장')),
          ),
        ],
      ),
    );
  }
}

class BankAccountForm extends ConsumerStatefulWidget {
  const BankAccountForm({super.key, required this.initial});

  final BankAccount initial;

  @override
  ConsumerState<BankAccountForm> createState() => _BankAccountFormState();
}

class _BankAccountFormState extends ConsumerState<BankAccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final _bank = TextEditingController(text: widget.initial.bankName);
  late final _number = TextEditingController(
    text: widget.initial.accountNumber,
  );
  late final _holder = TextEditingController(text: widget.initial.holder);
  bool _saving = false;

  @override
  void didUpdateWidget(covariant BankAccountForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_saving) return;
    if (oldWidget.initial.bankName != widget.initial.bankName &&
        _bank.text == oldWidget.initial.bankName) {
      _bank.text = widget.initial.bankName;
    }
    if (oldWidget.initial.accountNumber != widget.initial.accountNumber &&
        _number.text == oldWidget.initial.accountNumber) {
      _number.text = widget.initial.accountNumber;
    }
    if (oldWidget.initial.holder != widget.initial.holder &&
        _holder.text == oldWidget.initial.holder) {
      _holder.text = widget.initial.holder;
    }
  }

  @override
  void dispose() {
    _bank.dispose();
    _number.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveBankAccount(
            await ref.requireAdminCampusId(),
            BankAccount(
              bankName: _bank.text,
              accountNumber: _number.text,
              holder: _holder.text,
            ),
          );
      ref.invalidate(bankAccountProvider);
      if (mounted) showSnack(context, '송금 계좌를 저장했습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v, String label) =>
        (v == null || v.trim().isEmpty) ? '${withObject(label)} 입력해 주세요.' : null;

    // 입력칸이 회색 면이라 카드 없이 흰 배경에 둔다.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('송금 계좌'),
            Text(
              '교재 신청 완료 화면과 이벤트 화면에서 회원에게 안내됩니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bank,
              decoration: const InputDecoration(labelText: '은행'),
              validator: (v) => required(v, '은행'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _number,
              decoration: const InputDecoration(
                labelText: '계좌번호',
                hintText: '예) 123-456-789012',
              ),
              validator: (v) => required(v, '계좌번호'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _holder,
              decoration: const InputDecoration(labelText: '예금주'),
              validator: (v) => required(v, '예금주'),
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
