import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import 'settings_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _store = SettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.paper,
      body: Column(
        children: [
          AppHeader(
            title: '设置',
            onBack: () => context.go(AppRoutes.home),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) {
                if (!_store.loaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                final s = _store.settings;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.space4,
                    AppTokens.space4,
                    AppTokens.space4,
                    AppTokens.space6 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    _GroupTitle('识别'),
                    _SettingsCard(
                      children: [
                        _SliderRow(
                          name: '识别置信阈值',
                          valueLabel: s.format('confidence'),
                          value: s.confidence,
                          min: 0.3,
                          max: 0.95,
                          onChanged: (v) =>
                              _store.update(s.copyWith(confidence: v)),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.space2),
                    Text(
                      '低于此置信度的识别结果将不展示字幕、不出声。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppTokens.space5),
                    _GroupTitle('机位阀门'),
                    _SettingsCard(
                      children: [
                        _SliderRow(
                          name: 'depth.soft',
                          valueLabel: s.format('depthSoft'),
                          value: s.depthSoft,
                          min: 0.05,
                          max: 0.5,
                          onChanged: (v) =>
                              _store.update(s.copyWith(depthSoft: v)),
                        ),
                        _SliderRow(
                          name: 'depth.hard',
                          valueLabel: s.format('depthHard'),
                          value: s.depthHard,
                          min: 0.3,
                          max: 0.95,
                          onChanged: (v) =>
                              _store.update(s.copyWith(depthHard: v)),
                        ),
                        _SliderRow(
                          name: 'bias.soft',
                          valueLabel: s.format('biasSoft'),
                          value: s.biasSoft,
                          min: 0.05,
                          max: 0.5,
                          onChanged: (v) =>
                              _store.update(s.copyWith(biasSoft: v)),
                        ),
                        _SliderRow(
                          name: 'bias.hard',
                          valueLabel: s.format('biasHard'),
                          value: s.biasHard,
                          min: 0.4,
                          max: 0.95,
                          onChanged: (v) =>
                              _store.update(s.copyWith(biasHard: v)),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.space2),
                    Text(
                      '控制远近与偏移提示的软/硬阈值。一期冷启动加载，原型改动仅保存在本机。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppTokens.space4),
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          '高级（抖动与播音）',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        children: [
                          _SettingsCard(
                            children: [
                              _SliderRow(
                                name: '抖动灵敏度',
                                valueLabel: s.format('shakeSensitivity'),
                                value: s.shakeSensitivity,
                                min: 0.1,
                                max: 1,
                                onChanged: (v) => _store
                                    .update(s.copyWith(shakeSensitivity: v)),
                              ),
                              _SliderRow(
                                name: '播音启动水位 T_prime',
                                valueLabel: s.format('tPrimeMs'),
                                value: s.tPrimeMs,
                                min: 80,
                                max: 120,
                                divisions: 40,
                                onChanged: (v) =>
                                    _store.update(s.copyWith(tPrimeMs: v)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.space6),
                    AppButton.ghost(
                      label: '恢复默认',
                      onPressed: () => _store.reset(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: AppTokens.textSm,
              color: AppTokens.fgMuted,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space4,
        AppTokens.space3,
        AppTokens.space4,
        AppTokens.space2,
      ),
      decoration: BoxDecoration(
        color: AppTokens.paperElevated,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(children: children),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.name,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String name;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space3),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: AppTokens.textSm,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: AppTokens.teal,
                  fontSize: AppTokens.textSm,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions ?? ((max - min) / 0.01).round(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
