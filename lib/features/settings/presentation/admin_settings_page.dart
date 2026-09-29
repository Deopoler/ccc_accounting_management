import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/bank_account.dart';
import 'settings_providers.dart';

class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(bankAccountProvider);
    return AsyncValueView(
      value: account,
      onRetry: () => ref.invalidate(bankAccountProvider),
      data: (a) => ScrollPageBody(
        maxWidth: 640,
        children: [
          _BankAccountForm(initial: a),
          const SizedBox(height: 16),
          const _DefaultPasswordInfo(),
        ],
      ),
    );
  }
}

class _BankAccountForm extends ConsumerStatefulWidget {
  const _BankAccountForm({required this.initial});

  final BankAccount initial;

  @override
  ConsumerState<_BankAccountForm> createState() => _BankAccountFormState();
}

class _BankAccountFormState extends ConsumerState<_BankAccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final _bank = TextEditingController(text: widget.initial.bankName);
  late final _number = TextEditingController(
    text: widget.initial.accountNumber,
  );
  late final _holder = TextEditingController(text: widget.initial.holder);
  bool _saving = false;

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
        (v == null || v.trim().isEmpty) ? '$label을(를) 입력해 주세요.' : null;

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

class _DefaultPasswordInfo extends StatelessWidget {
  const _DefaultPasswordInfo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('기본 비밀번호'),
            Text(
              '회원 관리 > 비밀번호 초기화에 쓰는 기본 비밀번호는 보안을 위해 앱이나 DB 에 저장하지 않고 '
              'Supabase Edge Function 의 secret(DEFAULT_PASSWORD)에만 둡니다.\n'
              '변경: Supabase Dashboard > Edge Functions > Secrets',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
