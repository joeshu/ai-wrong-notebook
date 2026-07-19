class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.maxConcurrency = 2,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String model;
  final String apiKey;

  /// 多题并发分析的最大并发度。0 或负数视为默认 2。
  final int maxConcurrency;

  /// 返回有效并发度（兜底默认 2）。
  int get effectiveMaxConcurrency => maxConcurrency > 0 ? maxConcurrency : 2;
}
