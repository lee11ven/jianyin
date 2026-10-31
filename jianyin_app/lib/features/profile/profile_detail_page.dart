import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/auth_store.dart';
import '../../session/session_models.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_header.dart';
import 'profile_widgets.dart';

class ProfileDetailPage extends StatefulWidget {
  const ProfileDetailPage({super.key});

  @override
  State<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<ProfileDetailPage> {
  final _auth = AuthStore();
  UserProfile? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      final cached = _auth.user;
      if (cached != null && mounted) {
        setState(() => _user = cached);
      }
      final fresh = await _auth.refreshMe();
      if (!mounted) return;
      setState(() {
        _user = fresh;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : '加载失败';
        _user ??= _auth.user;
      });
    }
  }

  Future<void> _openEdit() async {
    final changed = await context.push<bool>(AppRoutes.profileEdit);
    if (changed == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资料已更新')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppTokens.paper,
        body: Column(
          children: [
            AppHeader(
              title: '个人信息',
              onBack: () => context.pop(),
              trailing: HeaderTextButton(
                label: '编辑',
                enabled: user != null && !_loading,
                onPressed: user == null ? null : _openEdit,
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppTokens.space4,
                  AppTokens.space4,
                  AppTokens.space4,
                  AppTokens.space6 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  ProfileInkStage(
                    user: user,
                    compact: true,
                  ),
                  const SizedBox(height: AppTokens.space5),
                  if (_error != null) ...[
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
                    const SizedBox(height: AppTokens.space3),
                  ],
                  if (_loading && user == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (user != null) ...[
                    const ProfileSectionLabel('资料'),
                    ProfileSheet(
                      children: [
                        ProfileFactRow(
                          label: '昵称',
                          value: user.username,
                        ),
                        ProfileFactRow(
                          label: '手机号',
                          value: user.maskedPhone,
                        ),
                        ProfileFactRow(
                          label: '性别',
                          value: user.sexLabel,
                        ),
                        ProfileFactRow(
                          label: '会员',
                          value: user.planLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.space4),
                    const ProfileSectionLabel('账号'),
                    ProfileSheet(
                      children: [
                        ProfileFactRow(
                          label: '用户 ID',
                          value: user.userId,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.space5),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('编辑资料'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTokens.teal,
                          side: const BorderSide(color: AppTokens.teal),
                          minimumSize: const Size(
                            double.infinity,
                            AppTokens.touchMin,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusBtn,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
