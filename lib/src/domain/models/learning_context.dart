/// Learning context stored as reserved tags so existing Drift databases and
/// JSON backups remain compatible without a destructive schema migration.
/// Values are hidden from ordinary tag presentation by [QuestionRecord].
enum QuestionDifficulty { foundation, advanced, challenge, custom }

enum AttemptStatus { notAttempted, wrongAttempt, incomplete, unknown }

class LearningContextCodec {
  const LearningContextCodec._();

  static const _stagePrefix = '__system_learning_stage:';
  static const _difficultyPrefix = '__system_difficulty:';
  static const _attemptPrefix = '__system_attempt_status:';
  static const _studentWorkPrefix = '__system_student_work:';

  static String? learningStage(Iterable<String> tags) =>
      _readText(tags, _stagePrefix);

  static QuestionDifficulty? difficulty(Iterable<String> tags) =>
      _readEnum(tags, _difficultyPrefix, QuestionDifficulty.values);

  static AttemptStatus attemptStatus(Iterable<String> tags) =>
      _readEnum(tags, _attemptPrefix, AttemptStatus.values);

  static String? studentWork(Iterable<String> tags) =>
      _readText(tags, _studentWorkPrefix);

  static List<String> write({
    required Iterable<String> tags,
    String? learningStage,
    QuestionDifficulty? difficulty,
    AttemptStatus? attemptStatus,
    String? studentWork,
  }) {
    final prefixes = [_stagePrefix, _difficultyPrefix, _attemptPrefix, _studentWorkPrefix];
    final result = tags.where((tag) => !prefixes.any(tag.startsWith)).toList();
    _appendText(result, _stagePrefix, learningStage);
    if (difficulty != null) result.add('$_difficultyPrefix${difficulty.name}');
    if (attemptStatus != null) result.add('$_attemptPrefix${attemptStatus.name}');
    _appendText(result, _studentWorkPrefix, studentWork);
    return result;
  }

  static bool isReservedTag(String tag) => tag.startsWith(_stagePrefix) ||
      tag.startsWith(_difficultyPrefix) ||
      tag.startsWith(_attemptPrefix) ||
      tag.startsWith(_studentWorkPrefix);

  static String? _readText(Iterable<String> tags, String prefix) {
    for (final tag in tags) {
      if (tag.startsWith(prefix)) {
        final value = tag.substring(prefix.length).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  static T? _readEnum<T extends Enum>(Iterable<String> tags, String prefix, List<T> values) {
    final value = _readText(tags, prefix);
    if (value == null) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static void _appendText(List<String> tags, String prefix, String? value) {
    final normalized = value?.trim().replaceAll(',', '，');
    if (normalized != null && normalized.isNotEmpty) tags.add('$prefix$normalized');
  }
}
