import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_message.dart';
import '../domain/credentials.dart';
import 'auth_providers.dart';
import 'widgets/auth_card.dart';

/// 첫 로그인 강제 변경(must_change_password)과 일반 변경을 모두 처리한다.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool forced}) async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
            currentPassword: forced ? null : _current.text,
            newPassword: _next.text,
          );
      TextInput.finishAutofillContext();
      // 트리거가 must_change_password 를 해제했으므로 프로필을 다시 읽는다.
      ref.invalidate(currentProfileProvider);
      await ref.read(currentProfileProvider.future);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('비밀번호가 변경되었습니다.')));
      _leave();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forced =
        ref.watch(currentProfileProvider).value?.mustChangePassword ?? false;

    return AuthCard(
      title: forced ? '비밀번호를 변경해 주세요' : '비밀번호 변경',
      subtitle: forced
          ? '처음 로그인하셨습니다. 기본 비밀번호를 본인만 아는 새 비밀번호로 변경해야 서비스를 이용할 수 있습니다.'
          : '현재 비밀번호를 확인한 뒤 새 비밀번호로 변경합니다.',
      leading: forced
          ? null
          : IconButton(
              tooltip: '뒤로',
              icon: const Icon(Icons.arrow_back),
              onPressed: _leave,
            ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!forced) ...[
                TextFormField(
                  controller: _current,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '현재 비밀번호'),
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? '현재 비밀번호를 입력해 주세요.' : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _next,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '새 비밀번호',
                  helperText: '$minPasswordLength자 이상, 영문과 숫자 포함',
                ),
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final base = validateNewPassword(v);
                  if (base != null) return base;
                  if (!forced && v == _current.text) {
                    return '현재 비밀번호와 다른 비밀번호를 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(forced: forced),
                validator: (v) => v != _next.text ? '새 비밀번호가 일치하지 않습니다.' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(forced: forced),
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('변경하기'),
              ),
              if (forced) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => ref.read(authRepositoryProvider).signOut(),
                  child: const Text('로그아웃'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
