import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_message.dart';
import '../../campus/presentation/campus_providers.dart';
import '../domain/credentials.dart';
import 'auth_providers.dart';
import 'widgets/auth_card.dart';
import 'widgets/campus_field.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with CampusSelection<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _studentId = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _studentId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final campus = this.campus;
    if (campus == null) return; // 캠퍼스 필드의 검증 / 로딩 표시가 안내한다.
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            campus: campus,
            studentId: _studentId.text,
            password: _password.text,
          );
      await saveLastCampusCode(campus.code);
      TextInput.finishAutofillContext();
      // 이동은 라우터 가드가 처리한다.
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(campusesProvider); // 목록을 불러오면 다시 그린다.
    return AuthCard(
      title: 'CCC 회계',
      subtitle: '학번과 비밀번호로 로그인하세요.',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CampusField(
                value: campus,
                onChanged: pickCampus,
                enabled: !_submitting,
              ),
              TextFormField(
                controller: _studentId,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '학번',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                validator: validateStudentId,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '비밀번호 보기' : '비밀번호 숨기기',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v == null || v.isEmpty) ? '비밀번호를 입력해 주세요.' : null,
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
                    : const Text('로그인'),
              ),
              const SizedBox(height: 8),
              // 화면의 파란 버튼(CTA)은 로그인 하나. 가입은 글자 버튼으로 둔다.
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => context.go(AppRoutes.signup),
                child: const Text('처음 이용하시나요? 가입하기'),
              ),
              const SizedBox(height: 16),
              Text(
                '비밀번호를 잊었다면 회계 담당자에게 초기화를 요청하세요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
