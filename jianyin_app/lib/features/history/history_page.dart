import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/api_client.dart';
import '../../session/auth_store.dart';
import '../../session/session_models.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_header.dart';
import 'export_calendar_sheet.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _auth = AuthStore();
  final _api = ApiClient();

  List<HistoryDay> _days = const [];
  bool _loading = true;
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
      final days = await _api.history(token: token);
      if (!mounted) return;
      setState(() {
        _days = days;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.paper,
      body: Column(
        children: [
          AppHeader(
            title: '历史字幕',
            onBack: () => context.pop(),
            trailing: HeaderTextButton(
              label: '导出',
              onPressed: _days.isEmpty
                  ? null
                  : () => showExportCalendarSheet(context, days: _days),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTokens.space4),
        children: [
          Text(
            _error!,
            style: const TextStyle(color: AppTokens.danger),
          ),
          const SizedBox(height: AppTokens.space3),
          TextButton(onPressed: _load, child: const Text('重试')),
        ],
      );
    }
    if (_days.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTokens.space4),
        children: [
          const SizedBox(height: 80),
          Text(
            '暂无字幕历史',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTokens.fgMuted,
                ),
          ),
          const SizedBox(height: AppTokens.space2),
          Text(
            '进入识别页完成手语转译后，记录会出现在这里',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppTokens.space4,
        AppTokens.space4,
        AppTokens.space4,
        AppTokens.space6 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        for (final day in _days) ...[
          Text(
            day.label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: AppTokens.textSm,
                  color: AppTokens.fgMuted,
                ),
          ),
          const SizedBox(height: AppTokens.space2),
          for (final item in day.items) ...[
            _HistoryCard(item: item),
            const SizedBox(height: AppTokens.space3),
          ],
          const SizedBox(height: AppTokens.space3),
        ],
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.space4),
      decoration: BoxDecoration(
        color: AppTokens.paperElevated,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.time,
            style: const TextStyle(
              fontSize: AppTokens.textXs,
              color: AppTokens.fgMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTokens.space2),
          Text(
            item.text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
