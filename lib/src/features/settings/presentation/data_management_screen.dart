import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smart_wrong_notebook/src/data/files/backup_attachment_integrity.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class DataManagementScreen extends ConsumerStatefulWidget {
  const DataManagementScreen({super.key});

  @override
  ConsumerState<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends ConsumerState<DataManagementScreen> {
  static const _backupSchemaVersion = 5;
  static const _lastImportKey = 'backup_last_import_v1';
  _ImportUndo? _lastImport;
  String? _lastBackupLabel;

  @override
  void initState() {
    super.initState();
    _loadLastImport();
  }

  Future<void> _loadLastImport() async {
    final raw = (await SharedPreferences.getInstance()).getString(_lastImportKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) setState(() => _lastImport = _ImportUndo.fromJson(decoded));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    final reviewLogsAsync = ref.watch(reviewLogListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/settings'),
        ),
      ),
      body: questionsAsync.when(
        data: (questions) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _BackupStatusCard(
              questionCount: questions.length,
              lastBackupLabel: _lastBackupLabel,
              onBackup: questions.isEmpty ? null : () => _exportQuestions(context, ref, questions),
              onRestore: () => _importQuestions(context, ref),
              onUndo: _lastImport == null ? null : () => _undoLastImport(context, ref),
            ),
            const SizedBox(height: 8),
            const Text('删除所有错题和复习记录，不可恢复', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.trash,
              iconColor: Colors.red,
              title: '清空所有数据',
              titleColor: Colors.red,
              subtitle: '删除所有错题和复习记录；建议先创建完整备份',
              onTap: () => _confirmClearAll(context, ref, questions.length),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('存储概览'),
            const SizedBox(height: 8),
            _DataCard(icon: CupertinoIcons.tray, title: '题库总量', trailing: '${questions.length} 题'),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.clock,
              title: '复习记录总量',
              trailingWidget: reviewLogsAsync.when(
                data: (logs) => Text('${logs.length} 条', style: _trailingStyle(context)),
                loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) => Text('加载失败', style: _subtitleStyle(context)),
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('学习资料导出'),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.rectangle_stack,
              title: '组卷与打印工作台',
              subtitle: questions.isEmpty ? '题库为空，进入查看添加错题说明' : '筛选、选题、调整顺序后导出打印',
              onTap: () => context.push('/worksheet'),
            ),
            const SizedBox(height: 8),
            _DataCard(
              icon: CupertinoIcons.doc_text,
              title: '导出错题讲义 PDF',
              subtitle: '选择自测卷、答案讲义或错因复盘版式',
              onTap: questions.isEmpty ? null : () => _showPdfExportSheet(context, questions),
            ),
            const SizedBox(height: 8),
            Builder(builder: (cardContext) => _DataCard(
              icon: CupertinoIcons.doc_richtext,
              title: '导出可打印 HTML',
              subtitle: '按学科整理，可在浏览器打开后打印',
              onTap: questions.isEmpty ? null : () => HtmlExportService.shareHtml(cardContext, questions),
            )),
            const SizedBox(height: 20),
            const _SectionTitle('清理与危险操作'),
            const SizedBox(height: 8),
          ],
        ),
        loading: () => const AppLoadingState(label: '正在读取本地数据…'),
        error: (_, __) => AppErrorState(message: '数据暂时无法读取。', onRetry: () => ref.invalidate(questionListProvider)),
      ),
    );
  }

  Future<void> _exportQuestions(
      BuildContext context, WidgetRef ref, List<QuestionRecord> questions) async {
    final reviewLogs = await ref.read(reviewLogRepositoryProvider).listAll();
    final approved = await _showBackupPreview(context, questions, reviewLogs.length);
    if (approved != true || !context.mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/exports');
      await exportDir.create(recursive: true);
      final now = DateTime.now();
      final attachments = await _buildAttachmentBackup(questions);
      final attachmentIndex = attachments.map((item) => <String, dynamic>{
        'questionId': item['questionId'], 'fileName': item['fileName'],
        'sha256': item['sha256'], 'byteSize': base64Decode(item['contentBase64'] as String).length,
      }).toList();
      final manifest = <String, dynamic>{
        'format': 'smart-wrong-notebook-backup',
        'schemaVersion': _backupSchemaVersion,
        'generatedAt': now.toIso8601String(),
        'questionCount': questions.length,
        'reviewLogCount': reviewLogs.length,
        'attachmentCount': attachments.length,
        'attachments': attachmentIndex,
      };
      final archive = Archive();
      archive.addFile(ArchiveFile('manifest.json', 0, utf8.encode(jsonEncode(manifest))));
      archive.addFile(ArchiveFile('questions.json', 0, utf8.encode(jsonEncode(questions.map(_questionToJson).toList()))));
      archive.addFile(ArchiveFile('review_logs.json', 0, utf8.encode(jsonEncode(reviewLogs.map(_reviewLogToJson).toList()))));
      for (final attachment in attachments) {
        final content = attachment['contentBase64'] as String?;
        final questionId = attachment['questionId'] as String?;
        final fileName = attachment['fileName'] as String?;
        if (content == null || questionId == null || fileName == null) continue;
        archive.addFile(ArchiveFile('attachments/${questionId}_$fileName', 0, base64Decode(content)));
      }
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw const FileSystemException('无法创建备份包');
      final file = File('${exportDir.path}/wrong-notebook-${now.millisecondsSinceEpoch}.wnb');
      await file.writeAsBytes(encoded, flush: true);
      if (!mounted) return;
      setState(() => _lastBackupLabel = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} · ${questions.length} 题');
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      await Share.shareXFiles([XFile(file.path)], subject: 'Wrong notebook backup', fileNameOverrides: ['wrong-notebook-backup.wnb'], sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败: $e')));
    }
  }

  Future<bool?> _showBackupPreview(BuildContext context, List<QuestionRecord> questions, int logCount) async {
    final attachments = await _buildAttachmentBackup(questions);
    final metadataBytes = utf8.encode(jsonEncode(attachments.map((item) {
      final copy = Map<String, dynamic>.from(item)..remove('contentBase64');
      return copy;
    }).toList())).length;
    final bytes = utf8.encode(jsonEncode(questions.map(_questionToJson).toList())).length + metadataBytes + attachments.fold<int>(0, (sum, item) => sum + base64Decode(item['contentBase64'] as String).length);
    final estimate = _formatBytes(bytes);
    return showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('创建完整备份'),
      content: Text('将创建可在新设备恢复的 .wnb 备份包：\n\n✓ ${questions.length} 道错题\n✓ $logCount 条复习记录\n✓ ${attachments.length} 张题图\n预计大小：约 $estimate（压缩后可能更小）\n\n不会包含 API Key、临时导入会话和未确认的工作台草稿。'),
      actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建并保存'))],
    ));
  }

  String _formatBytes(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(1)} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';


  Future<dynamic> _readBackupFile(File file) async {
    if (!file.path.toLowerCase().endsWith('.wnb')) return jsonDecode(await file.readAsString());
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    String readText(String name) {
      final entry = archive.files.where((item) => item.name == name).firstOrNull;
      if (entry == null) throw const FormatException('备份包缺少必要文件');
      return utf8.decode(entry.content as List<int>);
    }
    final manifest = Map<String, dynamic>.from(jsonDecode(readText('manifest.json')) as Map);
    final index = manifest['attachments'] is List ? manifest['attachments'] as List : const <dynamic>[];
    final attachments = <Map<String, dynamic>>[];
    var corrupt = 0;
    for (final item in index) {
      if (item is! Map) continue;
      final questionId = item['questionId'];
      final fileName = item['fileName'];
      if (questionId is! String || fileName is! String) continue;
      final entry = archive.files.where((file) => file.name == 'attachments/${questionId}_$fileName').firstOrNull;
      if (entry == null || !entry.isFile) { corrupt++; continue; }
      final bytes = Uint8List.fromList(entry.content as List<int>);
      if (item['byteSize'] != bytes.length || !BackupAttachmentIntegrity.matches(bytes, item['sha256'] as String?)) { corrupt++; continue; }
      attachments.add(<String, dynamic>{'questionId': questionId, 'fileName': fileName, 'contentBase64': base64Encode(bytes), 'sha256': item['sha256']});
    }
    return <String, dynamic>{...manifest, 'questions': jsonDecode(readText('questions.json')), 'reviewLogs': jsonDecode(readText('review_logs.json')), 'attachments': attachments, 'corruptAttachmentCount': corrupt};
  }

  _BackupPreview _backupPreview(dynamic decoded) {
    final questions = _questionsFromBackup(decoded);
    final attachments = decoded is Map && decoded['attachments'] is List ? (decoded['attachments'] as List).length : 0;
    final logs = decoded is Map && decoded['reviewLogs'] is List ? (decoded['reviewLogs'] as List).length : 0;
    final corrupt = decoded is Map && decoded['corruptAttachmentCount'] is int ? decoded['corruptAttachmentCount'] as int : 0;
    return _BackupPreview(questions.length, logs, attachments, corrupt, decoded is Map ? decoded['generatedAt'] as String? : null);
  }

  Future<bool?> _showRestorePreview(BuildContext context, _BackupPreview preview) => showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('确认恢复备份'),
    content: Text('备份内容：\n✓ ${preview.questions} 道错题\n✓ ${preview.logs} 条复习记录\n✓ ${preview.attachments} 张题图${preview.corruptAttachments == 0 ? '' : '\n⚠ ${preview.corruptAttachments} 张题图校验失败，将跳过'}${preview.generatedAt == null ? '' : '\n\n创建时间：${preview.generatedAt}'}\n\n将以“合并”方式恢复；当前已有的同 ID 题目会跳过，不会清空现有题库。'),
    actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始恢复'))],
  ));

  Future<void> _showRestoreResult(BuildContext context, int questions, int logs, int images, int skipped) => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('恢复完成'),
    content: Text('✓ 新增错题：$questions 道\n✓ 恢复复习记录：$logs 条\n✓ 恢复题图：$images 张\n⊘ 跳过重复或无效记录：$skipped 条\n\n可在本页顶部撤销本次恢复。'),
    actions: <Widget>[FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('完成'))],
  ));

  Future<void> _undoLastImport(BuildContext context, WidgetRef ref) async {
    final undo = _lastImport;
    if (undo == null) return;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('撤销本次恢复？'), content: Text('将删除本次恢复的 ${undo.questionIds.length} 道题、${undo.reviewLogIds.length} 条复习记录及题图。'), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('撤销'))]));
    if (yes != true) return;
    final repo = ref.read(questionRepositoryProvider);
    for (final id in undo.questionIds) { await repo.delete(id); }
    await ref.read(reviewLogRepositoryProvider).deleteByIds(undo.reviewLogIds);
    for (final path in undo.imagePaths) { final file = File(path); if (await file.exists()) await file.delete(); }
    if (mounted) setState(() => _lastImport = null);
    await (await SharedPreferences.getInstance()).remove(_lastImportKey);
    invalidateQuestionList(ref);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已撤销本次恢复')));
  }

  Future<void> _persistLastImport(_ImportUndo undo) async {
    await (await SharedPreferences.getInstance()).setString(_lastImportKey, jsonEncode(undo.toJson()));
  }

  void _showPdfExportSheet(BuildContext context, List<QuestionRecord> questions) {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[const Text('导出错题讲义 PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('选择导出版本；当前导出全部题库。'), const SizedBox(height: 12), for (final mode in WorksheetExportMode.values) ListTile(title: Text(mode == WorksheetExportMode.practice ? '仅题目自测卷' : mode == WorksheetExportMode.answer ? '题目与答案讲义' : '错因复盘讲义'), onTap: () { Navigator.pop(sheetContext); PdfExportService.sharePdf(context, questions, mode: mode); })]))));
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

  Map<String, dynamic> _reviewLogToJson(ReviewLog log) => <String, dynamic>{
        'id': log.id,
        'questionRecordId': log.questionRecordId,
        'reviewedAt': log.reviewedAt.toIso8601String(),
        'result': log.result,
        'masteryAfter': log.masteryAfter.name,
      };

  Future<void> _importQuestions(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json', 'wnb']);
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.first.path!);
      final decoded = await _readBackupFile(file);
      final preview = _backupPreview(decoded);
      final proceed = await _showRestorePreview(context, preview);
      if (proceed != true || !context.mounted) return;
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
      final importedIds = <String>{};
      final restoredImagePaths = <String>[];

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
        if (restoredPath != null) restoredImagePaths.add(restoredPath);
        await repo.saveDraft(restoredPath == null
            ? record
            : record.copyWith(imagePath: restoredPath));
        importedIds.add(record.id);
        imported++;
      }

      final restoredReviewLogIds = await _restoreReviewLogs(
        decoded,
        ref,
        allowedQuestionIds: importedIds,
      );
      final undo = _ImportUndo(importedIds, restoredReviewLogIds.toSet(), restoredImagePaths);
      await _persistLastImport(undo);
      if (mounted) setState(() => _lastImport = undo);
      invalidateQuestionList(ref);

      if (!context.mounted) return;
      await _showRestoreResult(context, imported, restoredReviewLogIds.length, restoredImagePaths.length, skipped);
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
    if (decoded is! Map || decoded['attachments'] is! List) return const <String, String>{};
    final documents = await getApplicationDocumentsDirectory();
    final staging = Directory('${documents.path}/restore_staging_${DateTime.now().microsecondsSinceEpoch}');
    final attachmentDir = Directory('${documents.path}/imported_images');
    await staging.create(recursive: true);
    final restored = <String, String>{};
    try {
      for (final item in decoded['attachments'] as List) {
        if (item is! Map) continue;
        final questionId = item['questionId'];
        final content = item['contentBase64'];
        if (questionId is! String || questionId.isEmpty || !allowedIds.contains(questionId) || content is! String) continue;
        final bytes = base64Decode(content);
        if (!BackupAttachmentIntegrity.matches(bytes, item['sha256'] as String?)) continue;
        final rawName = item['fileName'] is String ? item['fileName'] as String : 'image.jpg';
        final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final staged = File('${staging.path}/${questionId}_$safeName');
        await staged.writeAsBytes(bytes, flush: true);
        restored[questionId] = staged.path;
      }
      await attachmentDir.create(recursive: true);
      final committed = <String, String>{};
      for (final entry in restored.entries) {
        final source = File(entry.value);
        final target = File('${attachmentDir.path}/${source.uri.pathSegments.last}');
        await source.rename(target.path);
        committed[entry.key] = target.path;
      }
      return committed;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<List<String>> _restoreReviewLogs(
    dynamic decoded,
    WidgetRef ref, {
    required Set<String> allowedQuestionIds,
  }) async {
    if (decoded is! Map || decoded['reviewLogs'] is! List) return const <String>[];
    final repository = ref.read(reviewLogRepositoryProvider);
    final existingIds = (await repository.listAll()).map((log) => log.id).toSet();
    final restored = <String>[];
    for (final raw in decoded['reviewLogs'] as List) {
      if (raw is! Map) continue;
      final log = _jsonToReviewLog(Map<String, dynamic>.from(raw));
      if (log == null ||
          !allowedQuestionIds.contains(log.questionRecordId) ||
          !existingIds.add(log.id)) {
        continue;
      }
      await repository.insert(log);
      restored.add(log.id);
    }
    return restored;
  }

  ReviewLog? _jsonToReviewLog(Map<String, dynamic> json) {
    final id = json['id'];
    final questionId = json['questionRecordId'];
    final reviewedAt = json['reviewedAt'];
    final result = json['result'];
    final masteryName = json['masteryAfter'];
    if (id is! String ||
        id.isEmpty ||
        questionId is! String ||
        questionId.isEmpty ||
        reviewedAt is! String ||
        result is! String ||
        masteryName is! String) {
      return null;
    }
    final timestamp = DateTime.tryParse(reviewedAt);
    if (timestamp == null) return null;
    final mastery = MasteryLevel.values.where((level) => level.name == masteryName);
    if (mastery.isEmpty) return null;
    return ReviewLog(
      id: id,
      questionRecordId: questionId,
      reviewedAt: timestamp,
      result: result,
      masteryAfter: mastery.first,
    );
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


class _ImportUndo {
  const _ImportUndo(this.questionIds, this.reviewLogIds, this.imagePaths);
  final Set<String> questionIds;
  final Set<String> reviewLogIds;
  final List<String> imagePaths;
  Map<String, dynamic> toJson() => <String, dynamic>{'questionIds': questionIds.toList(), 'reviewLogIds': reviewLogIds.toList(), 'imagePaths': imagePaths};
  factory _ImportUndo.fromJson(Map<String, dynamic> json) => _ImportUndo(
    (json['questionIds'] as List? ?? const <dynamic>[]).whereType<String>().toSet(),
    (json['reviewLogIds'] as List? ?? const <dynamic>[]).whereType<String>().toSet(),
    (json['imagePaths'] as List? ?? const <dynamic>[]).whereType<String>().toList(),
  );
}

class _BackupPreview {
  const _BackupPreview(this.questions, this.logs, this.attachments, this.corruptAttachments, this.generatedAt);
  final int questions;
  final int logs;
  final int attachments;
  final int corruptAttachments;
  final String? generatedAt;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));
}

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({required this.questionCount, required this.lastBackupLabel, this.onBackup, required this.onRestore, this.onUndo});
  final int questionCount;
  final String? lastBackupLabel;
  final VoidCallback? onBackup;
  final VoidCallback onRestore;
  final VoidCallback? onUndo;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    Row(children: <Widget>[const Icon(CupertinoIcons.shield_lefthalf_fill, color: Color(0xFF4F46E5)), const SizedBox(width: 10), Text('数据备份与迁移', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))]),
    const SizedBox(height: 8),
    Text(lastBackupLabel == null ? (questionCount == 0 ? '题库为空；保存错题后可创建完整备份。' : '尚未在本次使用中创建备份，建议在导入大量题目后保存。') : '最近备份：$lastBackupLabel', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    const SizedBox(height: 12),
    Wrap(spacing: 8, runSpacing: 8, children: <Widget>[FilledButton.icon(onPressed: onBackup, icon: const Icon(CupertinoIcons.arrow_down_doc), label: const Text('备份全部数据')), OutlinedButton.icon(onPressed: onRestore, icon: const Icon(CupertinoIcons.arrow_up_doc), label: const Text('从备份恢复')), if (onUndo != null) TextButton.icon(onPressed: onUndo, icon: const Icon(CupertinoIcons.arrow_uturn_left), label: const Text('撤销本次恢复'))]),
  ])));
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
