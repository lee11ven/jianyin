import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/auth_store.dart';
import '../../session/session_models.dart';
import '../../theme/tokens.dart';
import 'profile_widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
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
        _error = e is ApiException ? e.message : '加载失败，下拉可重试';
        _user ??= _auth.user;
      });
    }
  }

  Future<void> _openDetail() async {
    await context.push(AppRoutes.profileDetail);
    if (mounted) await _load();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需重新登录才能使用识别。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _auth.clear();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppTokens.paper,
        body: RefreshIndicator(
          color: AppTokens.teal,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ProfileInkStage(
                  user: _user,
                  padTopSafeArea: true,
                  actionLabel: '查看与编辑资料',
                  onTap: _user == null ? null : _openDetail,
                  leading: _InkBackButton(
                    onPressed: () => context.go(AppRoutes.home),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppTokens.space4,
                  AppTokens.space5,
                  AppTokens.space4,
                  AppTokens.space6 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_loading && _user == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!, onRetry: _load),
                        const SizedBox(height: AppTokens.space4),
                      ],
                      const ProfileSectionLabel('功能与服务'),
                      ProfileSheet(
                        children: [
                          ProfileDestinationTile(
                            label: '个人信息',
                            subtitle: '昵称、性别与账号',
                            icon: Icons.person_outline_rounded,
                            onTap: _openDetail,
                          ),
                          ProfileDestinationTile(
                            label: '历史字幕',
                            subtitle: '按日查看与导出',
                            icon: Icons.subtitles_outlined,
                            onTap: () => context.push(AppRoutes.history),
                          ),
                          ProfileDestinationTile(
                            label: '开通会员',
                            subtitle: _user?.planLabel ?? '免费版',
                            icon: Icons.workspace_premium_outlined,
                            accent: true,
                            onTap: () => context.push(AppRoutes.membership),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.space5),
                      const ProfileSectionLabel('账号'),
                      ProfileSheet(
                        children: [
                          ProfileDestinationTile(
                            label: '退出登录',
                            subtitle: '清除本机登录状态',
                            icon: Icons.logout_rounded,
                            danger: true,
                            onTap: _logout,
                          ),
                        ],
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InkBackButton extends StatelessWidget {
  const _InkBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: AppTokens.touchMin,
          height: AppTokens.touchMin,
          child: Icon(
            Icons.chevron_left_rounded,
            color: AppTokens.fgOnInk,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.space3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppTokens.danger,
                  fontSize: AppTokens.textSm,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
