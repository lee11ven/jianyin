import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../session/session_models.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/icon_btn.dart';

Future<void> showExportCalendarSheet(
  BuildContext context, {
  required List<HistoryDay> days,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ExportCalendarSheet(days: days),
  );
}

class ExportCalendarSheet extends StatefulWidget {
  const ExportCalendarSheet({super.key, required this.days});

  final List<HistoryDay> days;

  @override
  State<ExportCalendarSheet> createState() => _ExportCalendarSheetState();
}

class _ExportCalendarSheetState extends State<ExportCalendarSheet> {
  late final Map<String, HistoryDay> _byDay;
  late int _year;
  late int _month; // 0-based
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _byDay = {for (final d in widget.days) d.iso: d};
    final anchor = widget.days.isNotEmpty
        ? widget.days.last.iso
        : '2026-10-25';
    _year = int.parse(anchor.substring(0, 4));
    _month = int.parse(anchor.substring(5, 7)) - 1;
  }

  List<String> get _pickedSorted => _picked.toList()..sort();

  Future<void> _export() async {
    final list = _pickedSorted;
    if (list.isEmpty) return;

    final lines = <String>['见音 · 历史字幕', ''];
    for (final day in list) {
      final rec = _byDay[day]!;
      lines.add('${rec.label} $day');
      for (final item in rec.items) {
        lines.add(item.time);
        lines.add(item.text);
        lines.add('');
      }
    }

    final compact = list.map((d) => d.replaceAll('-', '')).toList();
    final name = compact.length == 1
        ? '见音字幕_${compact[0]}.txt'
        : '见音字幕_${compact.first}-${compact.last}.txt';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    // UTF-8 BOM
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(lines.join('\n'))];
    await file.writeAsBytes(bytes);

    if (!mounted) return;
    Navigator.of(context).pop();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _pickedSorted.length;
    return Container(
      decoration: const BoxDecoration(
        color: AppTokens.paperElevated,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppTokens.space4,
        AppTokens.space3,
        AppTokens.space4,
        AppTokens.space5 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AppIconBtn(
                tooltip: '上个月',
                onPressed: () {
                  setState(() {
                    _month -= 1;
                    if (_month < 0) {
                      _month = 11;
                      _year -= 1;
                    }
                  });
                },
                child: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '$_year年${_month + 1}月',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              AppIconBtn(
                tooltip: '下个月',
                onPressed: () {
                  setState(() {
                    _month += 1;
                    if (_month > 11) {
                      _month = 0;
                      _year += 1;
                    }
                  });
                },
                child: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          Row(
            children: [
              for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppTokens.textXs,
                      color: AppTokens.fgMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.space2),
          _CalGrid(
            year: _year,
            month: _month,
            byDay: _byDay,
            picked: _picked,
            onToggle: (iso) {
              setState(() {
                if (_picked.contains(iso)) {
                  _picked.remove(iso);
                } else {
                  _picked.add(iso);
                }
              });
            },
          ),
          const SizedBox(height: AppTokens.space3),
          Text(
            '有字幕的日期可选，无字幕的日期不可选。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTokens.space4),
          Row(
            children: [
              Expanded(
                child: AppButton.ghost(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: AppButton.primary(
                  label: n > 0 ? '导出（$n）' : '导出',
                  enabled: n > 0,
                  onPressed: n > 0 ? _export : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalGrid extends StatelessWidget {
  const _CalGrid({
    required this.year,
    required this.month,
    required this.byDay,
    required this.picked,
    required this.onToggle,
  });

  final int year;
  final int month;
  final Map<String, HistoryDay> byDay;
  final Set<String> picked;
  final ValueChanged<String> onToggle;

  String _iso(int y, int m, int d) {
    final mm = (m + 1).toString().padLeft(2, '0');
    final dd = d.toString().padLeft(2, '0');
    return '$y-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month + 1, 1);
    final startPad = (first.weekday + 6) % 7; // Monday-first
    final count = DateTime(year, month + 2, 0).day;
    final cells = <Widget>[];

    for (var i = 0; i < startPad; i++) {
      cells.add(const SizedBox(height: 40));
    }
    for (var d = 1; d <= count; d++) {
      final key = _iso(year, month, d);
      final has = byDay.containsKey(key);
      final isPicked = picked.contains(key);
      cells.add(
        AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: !has
                  ? Colors.transparent
                  : isPicked
                      ? AppTokens.teal
                      : AppTokens.tealSoft,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: has ? () => onToggle(key) : null,
                borderRadius: BorderRadius.circular(10),
                child: Center(
                  child: Text(
                    '$d',
                    style: TextStyle(
                      fontSize: AppTokens.textSm,
                      fontWeight: FontWeight.w600,
                      color: !has
                          ? AppTokens.fgMuted.withValues(alpha: 0.35)
                          : isPicked
                              ? Colors.white
                              : AppTokens.teal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}
