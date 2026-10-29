import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/api_client.dart';
import '../../session/auth_store.dart';
import '../../session/session_models.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  final _auth = AuthStore();
  final _api = ApiClient();

  List<MembershipPlan> _plans = const [];
  MembershipStatus? _status;
  bool _loading = true;
  bool _subscribing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.load();
      final token = _auth.token;
      if (token == null) {
        if (!mounted) return;
        context.go(AppRoutes.login);
        return;
      }
      final plans = await _api.membershipPlans(token: token);
      final status = await _api.membership(token: token);
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : '加载失败';
      });
    }
  }

  Future<void> _subscribe(MembershipPlan plan) async {
    if (plan.id == 'free' || _subscribing) return;
    final token = _auth.token;
    if (token == null) return;

    setState(() => _subscribing = true);
    try {
      final status = await _api.subscribe(token: token, planId: plan.id);
      await _auth.refreshMe();
      if (!mounted) return;
      setState(() => _status = status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已开通「${status.title}」')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : '开通失败'),
        ),
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.paper,
      body: Column(
        children: [
          AppHeader(
            title: '开通会员',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppTokens.space4,
                      AppTokens.space4,
                      AppTokens.space4,
                      AppTokens.space6 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(color: AppTokens.danger),
                        ),
                        TextButton(onPressed: _load, child: const Text('重试')),
                        const SizedBox(height: AppTokens.space4),
                      ],
                      if (_status != null) ...[
                        Text(
                          '当前：${_status!.title}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppTokens.space4),
                      ],
                      for (var i = 0; i < _plans.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppTokens.space4),
                        _PlanCard(
                          plan: _plans[i],
                          currentPlanId: _status?.planId ?? 'free',
                          busy: _subscribing,
                          onSubscribe: () => _subscribe(_plans[i]),
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.currentPlanId,
    required this.busy,
    required this.onSubscribe,
  });

  final MembershipPlan plan;
  final String currentPlanId;
  final bool busy;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final isCurrent = plan.id == currentPlanId;
    final featured = plan.featured;

    Widget button;
    if (plan.id == 'free' || isCurrent) {
      button = AppButton.ghost(
        label: isCurrent ? '当前方案' : '免费方案',
        enabled: false,
        onPressed: null,
      );
    } else {
      button = AppButton.primary(
        label: busy ? '开通中…' : '立即开通',
        enabled: !busy,
        onPressed: busy ? null : onSubscribe,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTokens.space5),
          decoration: BoxDecoration(
            color: AppTokens.paperElevated,
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(
              color: featured ? AppTokens.teal : AppTokens.border,
              width: featured ? 2 : 1,
            ),
            boxShadow: featured
                ? [
                    BoxShadow(
                      color: AppTokens.teal.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppTokens.space2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: plan.price,
                      style: const TextStyle(
                        fontSize: AppTokens.text2xl,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.fg,
                      ),
                    ),
                    TextSpan(
                      text: ' ${plan.unit}',
                      style: const TextStyle(
                        fontSize: AppTokens.textSm,
                        color: AppTokens.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.space4),
              for (final f in plan.features)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.space2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: AppTokens.teal,
                      ),
                      const SizedBox(width: AppTokens.space2),
                      Expanded(
                        child: Text(
                          f,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppTokens.space4),
              button,
            ],
          ),
        ),
        if (featured)
          Positioned(
            top: -10,
            right: AppTokens.space4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.space3,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppTokens.teal,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '推荐',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppTokens.textXs,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
