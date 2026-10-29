import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/auth_store.dart';
import '../../session/session_models.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_header.dart';
import '../../widgets/list_nav_tile.dart';

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
        _error = e is ApiException ? e.message : '加载失败';
        _user ??= _auth.user;
      });
    }
  }

  Future<void> _logout() async {
    await _auth.clear();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.paper,
      body: Column(
        children: [
          AppHeader(
            title: '个人中心',
            onBack: () => context.go(AppRoutes.home),
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
                if (_loading && _user == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _ProfileHero(user: _user),
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
                  const SizedBox(height: AppTokens.space5),
                  ListNavGroup(
                    children: [
                      ListNavTile(
                        label: '历史对话文本字幕',
                        icon: Icons.description_outlined,
                        onTap: () => context.push(AppRoutes.history),
                      ),
                      ListNavTile(
                        label: '开通会员',
                        icon: Icons.workspace_premium_outlined,
                        onTap: () => context.push(AppRoutes.membership),
                      ),
                      ListNavTile(
                        label: '退出登录',
                        icon: Icons.logout,
                        danger: true,
                        onTap: _logout,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final name = user?.username.isNotEmpty == true ? user!.username : '未登录';
    final phone = user?.maskedPhone ?? '—';
    final letter = user?.avatarLetter ?? '?';
    final plan = user?.planLabel ?? '免费版';

    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTokens.teal, Color(0xFF134E4A)],
            ),
          ),
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppTokens.textXl,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: AppTokens.textLg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                phone,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppTokens.space2),
              AppBadge(label: plan),
            ],
          ),
        ),
      ],
    );
  }
}
