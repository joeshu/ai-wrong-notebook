enum LayoutProviderType { currentVision, paddleCloud, mineruCloud, customHttp, manualOnly }

class LayoutProviderConfig {
  const LayoutProviderConfig({
    required this.type,
    this.baseUrl = '',
    this.apiKey = '',
  });

  final LayoutProviderType type;
  final String baseUrl;
  final String apiKey;

  bool get isReady => type == LayoutProviderType.manualOnly ||
      type == LayoutProviderType.currentVision ||
      (type == LayoutProviderType.paddleCloud && apiKey.isNotEmpty) ||
      (type == LayoutProviderType.mineruCloud && apiKey.isNotEmpty) ||
      (type == LayoutProviderType.customHttp && baseUrl.isNotEmpty);
}
