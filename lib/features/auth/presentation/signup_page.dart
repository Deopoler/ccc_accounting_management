import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_message.dart';
import '../domain/credentials.dart';
import 'auth_providers.dart';
import 'widgets/auth_card.dart';

/// 처음 이용하는 회원의 가입. 가입 후 관리자 승인 전까지는 승인 대기 화면만 보인다.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _studentId = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _studentId.dispose();
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signUp(
            studentId: _studentId.text,
            name: _name.text,
            password: _password.text,
          );
      TextInput.finishAutofillContext();
      // 가입과 동시에 로그인되고, 라우터 가드가 승인 대기 화면으로 보낸다.
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      title: '가입하기',
      subtitle: '학번과 이름을 정확히 입력해 주세요. 회계 담당자가 확인 후 승인하면 이용할 수 있습니다.',
      leading: IconButton(
        tooltip: '로그인으로',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(AppRoutes.login),
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _studentId,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '학번',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: '로그인 아이디로 사용되며 바꿀 수 없습니다.',
                ),
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                validator: validateStudentId,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '이름',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                validator: validateName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: Icon(Icons.lock_outline),
                  helperText: '$minPasswordLength자 이상, 영문과 숫자 포함',
                ),
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: validateNewPassword,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '비밀번호 확인',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _password.text ? '비밀번호가 일치하지 않습니다.' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('가입하기'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go(AppRoutes.login),
                child: const Text('이미 가입했다면 로그인'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
