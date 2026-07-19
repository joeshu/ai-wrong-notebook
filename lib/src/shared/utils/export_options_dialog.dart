import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_preview_screen.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 导出选项：模式 + 筛选后的题目 + 学生信息。
class ExportOptions {
  const ExportOptions({
    required this.mode,
    required this.filtered,
    this.studentInfo,
  });

  final WorksheetExportMode mode;
  final List<QuestionRecord> filtered;
  final ExportStudentInfo? studentInfo;
}

enum _TimeRange { all, days7, days30, days90 }

const Map<_TimeRange, String> _timeRangeLabels = {
  _TimeRange.all: '全部时间',
  _TimeRange.days7: '近 7 天',
  _TimeRange.days30: '近 30 天',
  _TimeRange.days90: '近 90 天',
};

/// 弹出导出选项对话框：选择模式、筛选题目、填写学生信息。
///
/// - [allowFilter] 为 false 时隐藏筛选区（例如组卷工作台已手动选题）。
/// - [allowPreview] 为 true 时显示「预览」按钮（桌面端无 WebView，强制关闭）。
/// 返回 null 表示用户取消或已通过预览页完成导出。
Future<ExportOptions?> showExportOptionsDialog(
  BuildContext context,
  List<QuestionRecord> questions, {
  bool allowFilter = true,
  bool allowPreview = true,
}) {
  return showDialog<ExportOptions?>(
    context: context,
    builder: (_) => _ExportOptionsDialog(
      questions: questions,
      allowFilter: allowFilter,
      allowPreview: allowPreview && !HtmlExportService.isDesktopPlatform,
    ),
  );
}

class _ExportOptionsDialog extends StatefulWidget {
  const _ExportOptionsDialog({
    required this.questions,
    required this.allowFilter,
    required this.allowPreview,
  });

  final List<QuestionRecord> questions;
  final bool allowFilter;
  final bool allowPreview;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  WorksheetExportMode _mode = WorksheetExportMode.answer;
  final Set<Subject> _subjects = {};
  final Set<MasteryLevel> _levels = {};
  _TimeRange _timeRange = _TimeRange.all;
  final _nameController = TextEditingController();
  final _classController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _classController.dispose();
    super.dispose();
  }

  List<QuestionRecord> get _filtered {
    if (!widget.allowFilter) return widget.questions;
    final now = DateTime.now();
    return widget.questions.where((q) {
      if (_subjects.isNotEmpty && !_subjects.contains(q.subject)) return false;
      if (_levels.isNotEmpty && !_levels.contains(q.masteryLevel)) return false;
      switch (_timeRange) {
        case _TimeRange.days7:
          if (now.difference(q.createdAt).inDays > 7) return false;
        case _TimeRange.days30:
          if (now.difference(q.createdAt).inDays > 30) return false;
        case _TimeRange.days90:
          if (now.difference(q.createdAt).inDays > 90) return false;
        case _TimeRange.all:
          break;
      }
      return true;
    }).toList();
  }

  ExportStudentInfo? get _studentInfo {
    if (_nameController.text.isEmpty && _classController.text.isEmpty) return null;
    return ExportStudentInfo(
      name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      className:
          _classController.text.trim().isEmpty ? null : _classController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: const Text('导出选项'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('试卷类型', style: _sectionStyle),
              for (final item in WorksheetExportMode.values)
                RadioListTile<WorksheetExportMode>(
                  dense: true,
                  value: item,
                  groupValue: _mode,
                  title: Text(item.label),
                  onChanged: (v) {
                    if (v != null) setState(() => _mode = v);
                  },
                ),
              if (widget.allowFilter) ...<Widget>[
                const Divider(),
                const Text('按学科筛选（不选=全部）', style: _sectionStyle),
                _chipGroup<Subject>(
                  values: Subject.values,
                  selected: _subjects,
                  label: (s) => s.label,
                  onToggle: (s) => setState(() {
                    if (!_subjects.add(s)) _subjects.remove(s);
                  }),
                ),
                const SizedBox(height: 8),
                const Text('按掌握程度筛选（不选=全部）', style: _sectionStyle),
                _chipGroup<MasteryLevel>(
                  values: MasteryLevel.values,
                  selected: _levels,
                  label: _masteryLabel,
                  onToggle: (l) => setState(() {
                    if (!_levels.add(l)) _levels.remove(l);
                  }),
                ),
                const SizedBox(height: 8),
                Row(children: <Widget>[
                  const Text('时间范围：', style: _sectionStyle),
                  DropdownButton<_TimeRange>(
                    value: _timeRange,
                    items: [
                      for (final r in _TimeRange.values)
                        DropdownMenuItem(value: r, child: Text(_timeRangeLabels[r]!)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _timeRange = v);
                    },
                  ),
                ]),
              ],
              const Divider(),
              const Text('学生信息（可选，填在封面）', style: _sectionStyle),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '姓名',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _classController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '班级',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '将导出 ${filtered.length} 题（共 ${widget.questions.length} 题）',
                style: TextStyle(
                  color: filtered.isEmpty ? Colors.red : Colors.green[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (widget.allowPreview)
          TextButton(
            onPressed: filtered.isEmpty ? null : _preview,
            child: const Text('预览'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: filtered.isEmpty ? null : () => _export(filtered),
          child: const Text('导出'),
        ),
      ],
    );
  }

  Future<void> _preview() async {
    final filtered = _filtered;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HtmlPreviewScreen(
          questions: filtered,
          mode: _mode,
          studentInfo: _studentInfo,
        ),
      ),
    );
    if (!mounted) return;
    // 预览页已提供分享/导出 PDF 入口，返回后直接关闭对话框。
    Navigator.of(context).pop(null);
  }

  void _export(List<QuestionRecord> filtered) {
    Navigator.of(context).pop(ExportOptions(
      mode: _mode,
      filtered: filtered,
      studentInfo: _studentInfo,
    ));
  }

  Widget _chipGroup<T>({
    required List<T> values,
    required Set<T> selected,
    required String Function(T) label,
    required ValueChanged<T> onToggle,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 0,
      children: [
        for (final v in values)
          FilterChip(
            label: Text(label(v)),
            selected: selected.contains(v),
            onSelected: (_) => onToggle(v),
          ),
      ],
    );
  }
}

const TextStyle _sectionStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 13,
);

String _masteryLabel(MasteryLevel level) => switch (level) {
      MasteryLevel.newQuestion => '待学习',
      MasteryLevel.reviewing => '复习中',
      MasteryLevel.mastered => '已掌握',
    };
