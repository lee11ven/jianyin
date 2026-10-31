import 'dart:async';

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
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _auth = AuthStore();

  bool _busy = false;
  bool _sendingOtp = false;
  int _otpCooldown = 0;
  Timer? _otpTimer;
  String? _error;

  @override
  void dispose() {
    _otpTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  void _startOtpCooldown([int seconds = 60]) {
    _otpTimer?.cancel();
    setState(() => _otpCooldown = seconds);
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_otpCooldown <= 1) {
        timer.cancel();
        setState(() => _otpCooldown = 0);
        return;
      }
      setState(() => _otpCooldown -= 1);
    });
  }

  Future<void> _sendOtp() async {
    final phoneErr = validatePhone(_phone.text);
    if (phoneErr != null) {
      setState(() => _error = phoneErr);
      return;
    }
    if (_sendingOtp || _otpCooldown > 0 || _busy) return;

    setState(() {
      _sendingOtp = true;
      _error = null;
    });

    try {
      final debugCode = await _auth.sendOtp(phone: _phone.text);
      if (!mounted) return;
      _startOtpCooldown();
      if (debugCode != null && debugCode.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调试验证码：$debugCode')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _submit() async {
    final phoneErr = validatePhone(_phone.text);
    final codeErr = validateOtpCode(_code.text);
    final passErr = validatePassword(_password.text, isNew: true);
    final confirmErr =
        validatePasswordConfirm(_password.text, _password2.text);
    if (phoneErr != null ||
        codeErr != null ||
        passErr != null ||
        confirmErr != null) {
      setState(() => _error = phoneErr ?? codeErr ?? passErr ?? confirmErr);
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
        code: _code.text.trim(),
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
    final otpBusy = _sendingOtp || _otpCooldown > 0 || _busy;
    final otpLabel = _sendingOtp
        ? '发送中…'
        : (_otpCooldown > 0 ? '${_otpCooldown}s' : '获取验证码');

    return AuthOverlapScaffold(
      kind: AuthStageKind.happiness,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                label: '手机号',
                controller: _phone,
                hint: '请输入手机号',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: AppTokens.space4),
              AppField(
                label: '验证码',
                controller: _code,
                hint: '请输入验证码',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                digitsOnly: true,
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                trailing: SizedBox(
                  height: AppTokens.touchMin,
                  child: TextButton(
                    onPressed: otpBusy ? null : _sendOtp,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTokens.teal,
                      disabledForegroundColor: AppTokens.fgMuted,
                      minimumSize: const Size(96, AppTokens.touchMin),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space3,
                      ),
                    ),
                    child: Text(
                      otpLabel,
                      style: const TextStyle(
                        fontSize: AppTokens.textSm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
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
