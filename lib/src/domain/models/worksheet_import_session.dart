import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// An in-memory staging area for a multi-page worksheet import.
/// Pages become independent question drafts only after the user reviews them.
class WorksheetImportSession {
  const WorksheetImportSession({
    required this.id,
    required this.pages,
    required this.createdAt,
  });

  final String id;
  final List<QuestionRecord> pages;
  final DateTime createdAt;

  int get pageCount => pages.length;
}
