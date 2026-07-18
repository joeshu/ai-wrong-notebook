import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:smart_wrong_notebook/src/data/files/backup_attachment_integrity.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';

class DataManagementScreen extends ConsumerWidget {
  const DataManagementScreen({super.key});

  static const _backupSchemaVersion = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionListProvider);
    final reviewLogsAsync = ref.watch(reviewLogListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
        leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_left),
            onPressed: () => Navigator.of(context).pop()),
      ),
      body: questionsAsync.when(
        data: (questions) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _DataCard(
              icon: CupertinoIcons.tray,
              title: '题库总量',
              trailing: '${questions.length} 题',
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.clock,
              title: '复习记录总量',
              trailingWidget: reviewLogsAsync.when(
                data: (logs) =>
                    Text('${logs.length} 条', style: _trailingStyle(context)),
                loading: () => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) => Text('加载失败', style: _subtitleStyle(context)),
              ),
            ),
            const SizedBox(height: 16),
            _DataCard(
              icon: CupertinoIcons.arrow_up,
              title: '导入错题',
              subtitle: '支持旧版 JSON 与版本化备份；重复题将自动跳过',
              onTap: () => _importQuestions(context, ref),
            ),
            const SizedBox(height: 8),
            Builder(builder: (cardContext) {
              return _DataCard(
                icon: CupertinoIcons.arrow_down,
                title: '导出当前题库',
                subtitle: '导出含题图的版本化 JSON 备份，可在新设备恢复',
                onTap: questions.isEmpty
                    ? null
                    : () => _exportQuestions(cardContext, questions),
              );
            }),
            const SizedBox(height: 8),
            Builder(builder: (cardContext) {
              return _DataCard(
                icon: CupertinoIcons.doc_text,
                title: '导出整理为 PDF',
                subtitle: '按学科整理，包含题目、分析、解题步骤',
                onTap: questions.isEmpty
                    ? null
                    : () => PdfExportService.sharePdf(cardContext, questions),
              );
            }),
            const SizedBox(height: 8),
            Builder(builder: (cardContext) {
              return _DataCard(
                icon: CupertinoIcons.doc_richtext,
                title: '导出为可打印文档 (HTML)',
                subtitle: '按学科整理，浏览器中打开可直接打印',
                onTap: questions.isEmpty
                    ? null
                    : () => HtmlExportService.shareHtml(cardContext, questions),
              );
            }),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.trash,
              iconColor: Colors.red,
              title: '清空所有数据',
              titleColor: Colors.red,
              subtitle: '删除所有错题和复习记录，不可恢复',
              onTap: () => _confirmClearAll(context, ref, questions.length),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  Future<void> _exportQuestions(
      BuildContext context, List<QuestionRecord> questions) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/exports');
      if (!exportDir.existsSync()) {
        await exportDir.create(recursive: true);
      }

      final now = DateTime.now();
      final filename =
          'wrong_notebook_${now.toIso8601String().replaceAll(':', '-')}.json';
      final file = File('${exportDir.path}/$filename');

      final backup = <String, dynamic>{
        'schemaVersion': _backupSchemaVersion,
        'generatedAt': now.toIso8601String(),
        'questionCount': questions.length,
        'attachments': await _buildAttachmentBackup(questions),
        'questions': questions.map(_questionToJson).toList(),
      };
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(backup));

      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles([XFile(file.path)],
          text: '导出 ${questions.length} 道错题',
          sharePositionOrigin: origin);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _buildAttachmentBackup(
      List<QuestionRecord> questions) async {
    final attachments = <Map<String, dynamic>>[];
    for (final question in questions) {
      if (question.imagePath.isEmpty) continue;
      final file = File(question.imagePath);
      if (!await file.exists()) continue;
      try {
        final bytes = await file.readAsBytes();
        attachments.add(<String, dynamic>{
          'questionId': question.id,
          'fileName': file.uri.pathSegments.isEmpty
              ? '${question.id}.jpg'
              : file.uri.pathSegments.last,
          'contentBase64': base64Encode(bytes),
          'sha256': BackupAttachmentIntegrity.sha256Hex(bytes),
        });
      } catch (_) {
        // A single unreadable original image must not block the data backup.
      }
    }
    return attachments;
  }

  Map<String, dynamic> _questionToJson(QuestionRecord q) => q.toJson();

  Future<void> _importQuestions(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      final list = _questionsFromBackup(decoded);
      final repo = ref.read(questionRepositoryProvider);
      final existingIds = (await repo.listAll()).map((q) => q.id).toSet();
      final importableIds = list
          .whereType<Map>()
          .map((item) => item['id'])
          .whereType<String>()
          .where((id) => id.isNotEmpty && !existingIds.contains(id))
          .toSet();
      final attachmentPaths =
          await _restoreAttachments(decoded, allowedIds: importableIds);
      int imported = 0;
      int skipped = 0;

      for (final item in list) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        final record = _jsonToQuestion(Map<String, dynamic>.from(item));
        if (record == null || record.id.isEmpty || !existingIds.add(record.id)) {
          skipped++;
          continue;
        }
        final restoredPath = attachmentPaths[record.id];
        await repo.saveDraft(restoredPath == null
            ? record
            : record.copyWith(imagePath: restoredPath));
        imported++;
      }

      invalidateQuestionList(ref);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $imported 道错题，跳过 $skipped 条重复或无效记录')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<Map<String, String>> _restoreAttachments(
    dynamic decoded, {
    required Set<String> allowedIds,
  }) async {
    if (decoded is! Map || decoded['attachments'] is! List) {
      return const <String, String>{};
    }
    final documents = await getApplicationDocumentsDirectory();
    final attachmentDir = Directory('${documents.path}/imported_images');
    if (!await attachmentDir.exists()) {
      await attachmentDir.create(recursive: true);
    }

    final restored = <String, String>{};
    for (final item in decoded['attachments'] as List) {
      if (item is! Map) continue;
      final questionId = item['questionId'];
      final content = item['contentBase64'];
      if (questionId is! String ||
          questionId.isEmpty ||
          !allowedIds.contains(questionId) ||
          content is! String) {
        continue;
      }
      try {
        final bytes = base64Decode(content);
        final expectedHash = item['sha256'];
        final hashMatches = BackupAttachmentIntegrity.matches(
          bytes,
          expectedHash is String ? expectedHash : null,
        );
        if (!hashMatches) {
          continue;
        }
        final rawName = item['fileName'] is String
            ? item['fileName'] as String
            : 'image.jpg';
        final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final target = File('${attachmentDir.path}/${questionId}_$safeName');
        await target.writeAsBytes(bytes, flush: true);
        restored[questionId] = target.path;
      } catch (_) {
        // Invalid or corrupt attachment: import the question without its image.
      }
    }
    return restored;
  }

  List<dynamic> _questionsFromBackup(dynamic decoded) {
    // Version 1 exports are a bare list. Version 2+ wraps the list in an
    // envelope so the format can evolve without breaking old user backups.
    if (decoded is List) return decoded;
    if (decoded is! Map) throw const FormatException('备份文件格式不正确');

    final version = decoded['schemaVersion'];
    if (version is int && version > _backupSchemaVersion) {
      throw FormatException('备份版本 $version 高于当前应用支持的版本');
    }
    final questions = decoded['questions'];
    if (questions is! List) throw const FormatException('备份中没有题目数据');
    return questions;
  }

  QuestionRecord? _jsonToQuestion(Map<String, dynamic> map) {
    try {
      return QuestionRecord.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref, int count) {
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('题库为空，无需清空')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: Text('确定要删除全部 $count 道错题及其复习记录吗？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllData(ref, context);
            },
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData(WidgetRef ref, BuildContext context) async {
    final repo = ref.read(questionRepositoryProvider);
    final all = await repo.listAll();
    for (final q in all) {
      await repo.delete(q.id);
    }
    await ref.read(reviewLogRepositoryProvider).clear();
    invalidateQuestionList(ref);
    ref.read(currentQuestionProvider.notifier).state = null;

    try {
      for (final q in all) {
        final file = File(q.imagePath);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空 ${all.length} 道错题')),
      );
    }
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingWidget,
    this.iconColor,
    this.titleColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurfaceVariant;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 24, color: effectiveIconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: _titleStyle(context, color: titleColor)),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: _subtitleStyle(context)),
                    ],
                  ],
                ),
              ),
              if (trailingWidget != null)
                trailingWidget!
              else if (trailing != null)
                Text(trailing!, style: _trailingStyle(context))
              else if (onTap != null)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 22,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _titleStyle(BuildContext context, {Color? color}) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: color ?? colorScheme.onSurface);
}

TextStyle _subtitleStyle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
      fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.35);
}

TextStyle _trailingStyle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface);
}
