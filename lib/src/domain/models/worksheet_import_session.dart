import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// An in-memory staging area for a multi-page worksheet import.
/// Pages become independent question drafts only after the user reviews them.
class WorksheetImportSession {
  const WorksheetImportSession({
    required this.id,
    required this.pages,
    required this.sourcePageIds,
    required this.createdAt,
  });

  final String id;
  /// Remaining work: source pages plus cropped, independently analysable items.
  final List<QuestionRecord> pages;
  /// Immutable IDs of the original full-page images. Other items are question
  /// candidates created from a confirmed region.
  final Set<String> sourcePageIds;
  final DateTime createdAt;

  int get pageCount => pages.length;

  WorksheetImportSession copyWith({List<QuestionRecord>? pages}) {
    return WorksheetImportSession(
      id: id,
      pages: pages ?? this.pages,
      sourcePageIds: sourcePageIds,
      createdAt: createdAt,
    );
  }
}
