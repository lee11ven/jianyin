import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/auth_store.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_field.dart';
import '../../widgets/brand_mark.dart';
import 'auth_stage_art.dart';
import 'auth_validators.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _auth = AuthStore();

  String _sex = 'unknown';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _phone.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phoneErr = validatePhone(_phone.text);
    final passErr = validatePassword(_password.text, isNew: true);
    final confirmErr =
        validatePasswordConfirm(_password.text, _password2.text);
    if (phoneErr != null || passErr != null || confirmErr != null) {
      setState(() => _error = phoneErr ?? passErr ?? confirmErr);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _auth.register(
        phone: _phone.text,
        password: _password.text,
        username: _username.text.trim().isEmpty ? null : _username.text,
        sex: _sex,
      );
      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthOverlapScaffold(
      kind: AuthStageKind.happiness,
      child: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              const SizedBox(height: AppTokens.space1),
              Text(
                '注册后，看见手语即可实时听见翻译',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppTokens.space5),
              AppField(
                label: '昵称（可选）',
                controller: _username,
                hint: '默认：用户+手机后四位',
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.nickname],
              ),
              const SizedBox(height: AppTokens.space4),
              AppField(
                label: '手机号',
                controller: _phone,
                hint: '请输入手机号',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: AppTokens.space4),
              Text(
                '性别',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: AppTokens.space2),
              Wrap(
                spacing: AppTokens.space2,
                children: [
                  for (final opt in const [
                    ('unknown', '保密'),
                    ('male', '男'),
                    ('female', '女'),
                  ])
                    ChoiceChip(
                      label: Text(opt.$2),
                      selected: _sex == opt.$1,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _sex = opt.$1),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.space4),
              AppField(
                label: '密码',
                controller: _password,
                hint: '至少 8 位',
                obscureText: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: AppTokens.space4),
              AppField(
                label: '确认密码',
                controller: _password2,
                hint: '再次输入密码',
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) {
                  if (!_busy) _submit();
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.space3),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTokens.danger,
                    fontSize: AppTokens.textSm,
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.space4),
              AppButton.primary(
                label: _busy ? '注册中…' : '注册',
                enabled: !_busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: AppTokens.space2),
              Center(
                child: Text.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: [
                      const TextSpan(text: '已有账号？'),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap:
                              _busy ? null : () => context.go(AppRoutes.login),
                          child: const Text(
                            '登录',
                            style: TextStyle(
                              color: AppTokens.teal,
                              fontSize: AppTokens.textSm,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
