enum LayoutProviderType { currentVision, customHttp, manualOnly }

class LayoutProviderConfig {
  const LayoutProviderConfig({
    required this.type,
    this.baseUrl = '',
    this.apiKey = '',
  });

  final LayoutProviderType type;
  final String baseUrl;
  final String apiKey;

  bool get isReady => type != LayoutProviderType.customHttp || baseUrl.isNotEmpty;
}
