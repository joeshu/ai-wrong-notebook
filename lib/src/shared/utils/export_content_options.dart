/// 导出内容选项：控制各导出格式中需要包含哪些字段。
///
/// 不同导出场景（Markdown / Anki / CSV / JSON）共用这套开关，
/// 默认全部开启，调用方可以通过 [copyWith] 关闭不需要的字段。
class ExportContentOptions {
  const ExportContentOptions({
    this.includeImage = true,
    this.includeKnowledgePoints = true,
    this.includeMistakeReason = true,
    this.includeCorrectAnswer = true,
    this.includeSolutionSteps = true,
    this.includeStudyAdvice = true,
    this.includeReviewCount = true,
    this.includeFavoriteMark = true,
    this.includeDates = true,
    this.includeExercises = true,
  });

  /// 是否包含题图（题图引用或"见原图"说明）。
  final bool includeImage;

  /// 是否包含知识点。
  final bool includeKnowledgePoints;

  /// 是否包含错因分析。
  final bool includeMistakeReason;

  /// 是否包含正确答案。
  final bool includeCorrectAnswer;

  /// 是否包含解题步骤。
  final bool includeSolutionSteps;

  /// 是否包含学习建议。
  final bool includeStudyAdvice;

  /// 是否包含复习次数。
  final bool includeReviewCount;

  /// 是否包含收藏标记。
  final bool includeFavoriteMark;

  /// 是否包含创建/复习日期。
  final bool includeDates;

  /// 是否包含变式练习（生成的同类题）。
  final bool includeExercises;

  /// 默认全开选项，方便调用方快速获取一份"完整导出"配置。
  static const ExportContentOptions all = ExportContentOptions();

  /// 全关，调用方再逐项打开。
  static const ExportContentOptions none = ExportContentOptions(
    includeImage: false,
    includeKnowledgePoints: false,
    includeMistakeReason: false,
    includeCorrectAnswer: false,
    includeSolutionSteps: false,
    includeStudyAdvice: false,
    includeReviewCount: false,
    includeFavoriteMark: false,
    includeDates: false,
    includeExercises: false,
  );

  ExportContentOptions copyWith({
    bool? includeImage,
    bool? includeKnowledgePoints,
    bool? includeMistakeReason,
    bool? includeCorrectAnswer,
    bool? includeSolutionSteps,
    bool? includeStudyAdvice,
    bool? includeReviewCount,
    bool? includeFavoriteMark,
    bool? includeDates,
    bool? includeExercises,
  }) {
    return ExportContentOptions(
      includeImage: includeImage ?? this.includeImage,
      includeKnowledgePoints:
          includeKnowledgePoints ?? this.includeKnowledgePoints,
      includeMistakeReason: includeMistakeReason ?? this.includeMistakeReason,
      includeCorrectAnswer:
          includeCorrectAnswer ?? this.includeCorrectAnswer,
      includeSolutionSteps:
          includeSolutionSteps ?? this.includeSolutionSteps,
      includeStudyAdvice: includeStudyAdvice ?? this.includeStudyAdvice,
      includeReviewCount: includeReviewCount ?? this.includeReviewCount,
      includeFavoriteMark: includeFavoriteMark ?? this.includeFavoriteMark,
      includeDates: includeDates ?? this.includeDates,
      includeExercises: includeExercises ?? this.includeExercises,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportContentOptions &&
          runtimeType == other.runtimeType &&
          includeImage == other.includeImage &&
          includeKnowledgePoints == other.includeKnowledgePoints &&
          includeMistakeReason == other.includeMistakeReason &&
          includeCorrectAnswer == other.includeCorrectAnswer &&
          includeSolutionSteps == other.includeSolutionSteps &&
          includeStudyAdvice == other.includeStudyAdvice &&
          includeReviewCount == other.includeReviewCount &&
          includeFavoriteMark == other.includeFavoriteMark &&
          includeDates == other.includeDates &&
          includeExercises == other.includeExercises;

  @override
  int get hashCode => Object.hash(
        includeImage,
        includeKnowledgePoints,
        includeMistakeReason,
        includeCorrectAnswer,
        includeSolutionSteps,
        includeStudyAdvice,
        includeReviewCount,
        includeFavoriteMark,
        includeDates,
        includeExercises,
      );
}
