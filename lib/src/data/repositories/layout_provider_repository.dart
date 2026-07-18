import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';

class LayoutProviderRepository {
  static const _configKey = 'layout_provider_config_v1';
  static const _apiKey = 'layout_provider_api_key_v1';
  static const _secondaryApiKey = 'layout_provider_secondary_api_key_v1';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<LayoutProviderConfig> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_configKey);
    if (raw == null || raw.isEmpty) {
      return const LayoutProviderConfig(type: LayoutProviderType.currentVision);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = LayoutProviderType.values.firstWhere(
        (item) => item.name == json['type'],
        orElse: () => LayoutProviderType.currentVision,
      );
      String apiKey = '';
      String secondaryApiKey = '';
      try {
        apiKey = await _secureStorage.read(key: _apiKey) ?? '';
        secondaryApiKey = await _secureStorage.read(key: _secondaryApiKey) ?? '';
      } catch (_) {
        // Do not erase the selected service merely because Keychain is
        // temporarily unavailable. The UI can now report that re-entry is needed.
      }
      return LayoutProviderConfig(
        type: type,
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: apiKey,
        secondaryApiKey: secondaryApiKey,
      );
    } catch (_) {
      return const LayoutProviderConfig(type: LayoutProviderType.currentVision);
    }
  }

  Future<void> save(LayoutProviderConfig config) async {
    await _secureStorage.write(key: _apiKey, value: config.apiKey);
    await _secureStorage.write(key: _secondaryApiKey, value: config.secondaryApiKey);
    await (await SharedPreferences.getInstance()).setString(_configKey, jsonEncode({
      'type': config.type.name,
      'baseUrl': config.baseUrl,
    }));
  }
}
