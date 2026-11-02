import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/auth_store.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_field.dart';
import '../../widgets/app_header.dart';
import '../auth/auth_validators.dart';
import 'profile_widgets.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _auth = AuthStore();
  final _username = TextEditingController();

  String _sex = 'unknown';
  String? _letter;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.load();
      if (_auth.token == null) {
        if (!mounted) return;
        context.go(AppRoutes.login);
        return;
      }
      var user = _auth.user;
      user ??= await _auth.refreshMe();
      if (!mounted) return;
      _username.text = user.username;
      setState(() {
        _sex = user!.sex;
        _letter = user.avatarLetter;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = authErrorMessage(e);
      });
    }
  }

  Future<void> _save() async {
    final name = _username.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }
    if (name.length > 32) {
      setState(() => _error = '昵称最多 32 个字符');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _auth.updateProfile(username: name, sex: _sex);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _previewLetter {
    final t = _username.text.trim();
    if (t.isNotEmpty) return t.substring(0, 1);
    return _letter ?? '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.paper,
      body: Column(
        children: [
          AppHeader(
            title: '编辑资料',
            onBack: _saving ? null : () => context.pop(false),
            trailing: HeaderTextButton(
              label: _saving ? '保存中' : '保存',
              enabled: !_loading && !_saving,
              onPressed: _saving || _loading ? null : _save,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppTokens.space4,
                      AppTokens.space5,
                      AppTokens.space4,
                      AppTokens.space6 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      Center(
                        child: Column(
                          children: [
                            ProfileIdentityMark(
                              letter: _previewLetter,
                              size: 84,
                            ),
                            const SizedBox(height: AppTokens.space3),
                            Text(
                              '头像取昵称首字',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTokens.space5),
                      AppField(
                        label: '昵称',
                        controller: _username,
                        hint: '别人如何称呼你',
                        maxLength: 32,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.nickname],
                        enabled: !_saving,
                        onSubmitted: (_) {
                          if (!_saving) _save();
                        },
                      ),
                      const SizedBox(height: AppTokens.space5),
                      Text(
                        '性别',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: AppTokens.fg,
                            ),
                      ),
                      const SizedBox(height: AppTokens.space2),
                      ProfileSexSegment(
                        value: _sex,
                        enabled: !_saving,
                        onChanged: (v) => setState(() => _sex = v),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppTokens.space4),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppTokens.danger,
                              fontSize: AppTokens.textSm,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppTokens.space5),
                      AppButton.primary(
                        label: _saving ? '保存中…' : '保存更改',
                        enabled: !_saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
