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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthStore();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth.rememberedPhone().then((phone) {
      if (!mounted || phone == null || phone.isEmpty) return;
      _phone.text = phone;
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phoneErr = validatePhone(_phone.text);
    final passErr = validatePassword(_password.text);
    if (phoneErr != null || passErr != null) {
      setState(() => _error = phoneErr ?? passErr);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _auth.login(phone: _phone.text, password: _password.text);
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
      kind: AuthStageKind.hello,
      child: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              const SizedBox(height: AppTokens.space1),
              Text(
                '看见手语，实时听见翻译',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppTokens.space5),
              AppField(
                label: '手机号',
                controller: _phone,
                hint: '请输入手机号',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: AppTokens.space4),
              AppField(
                label: '密码',
                controller: _password,
                hint: '请输入密码',
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
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
                label: _busy ? '登录中…' : '登录',
                enabled: !_busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: AppTokens.space2),
              Center(
                child: Text.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: [
                      const TextSpan(text: '没有账号？'),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: _busy
                              ? null
                              : () => context.go(AppRoutes.register),
                          child: const Text(
                            '注册',
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
