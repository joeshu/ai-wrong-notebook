import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';

class LayoutProviderConfigScreen extends ConsumerStatefulWidget {
  const LayoutProviderConfigScreen({super.key});
  @override
  ConsumerState<LayoutProviderConfigScreen> createState() => _LayoutProviderConfigScreenState();
}

class _LayoutProviderConfigScreenState extends ConsumerState<LayoutProviderConfigScreen> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  LayoutProviderType _type = LayoutProviderType.currentVision;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() { super.initState(); _url = TextEditingController(); _key = TextEditingController(); }
  @override
  void dispose() { _url.dispose(); _key.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (_loaded) return;
    final config = await restoreLayoutProviderConfig(ref);
    if (!mounted) return;
    setState(() { _type = config.type; _url.text = config.baseUrl; _key.text = config.apiKey; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    _load();
    return Scaffold(
      appBar: AppBar(title: const Text('试卷版面识别')),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const Text('候选题框来源', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        RadioListTile<LayoutProviderType>(
          value: LayoutProviderType.currentVision, groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
          title: const Text('当前 AI 视觉模型'),
          subtitle: const Text('零额外配置；复用 AI 服务商配置生成候选框。'),
        ),
        RadioListTile<LayoutProviderType>(
          value: LayoutProviderType.customHttp, groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
          title: const Text('NAS / MinerU / 自定义 HTTP 服务'),
          subtitle: const Text('适用于 PP-Structure Docker、MinerU 网关或自建版面服务。'),
        ),
        RadioListTile<LayoutProviderType>(
          value: LayoutProviderType.manualOnly, groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
          title: const Text('仅手动框选'),
          subtitle: const Text('不上传整页试卷到任何版面识别服务。'),
        ),
        if (_type == LayoutProviderType.customHttp) ...<Widget>[
          const SizedBox(height: 16),
          TextField(controller: _url, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '服务地址', hintText: 'http://nas.local:8000')),
          const SizedBox(height: 12),
          TextField(controller: _key, obscureText: true,
              decoration: const InputDecoration(labelText: '访问令牌（可选）', hintText: 'Bearer Token 将安全存储')),
          const SizedBox(height: 12),
          const _ProtocolCard(),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存...' : '保存版面识别设置'),
        ),
      ]),
    );
  }

  Future<void> _save() async {
    if (_type == LayoutProviderType.customHttp && _url.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写 NAS 或云 API 服务地址')));
      return;
    }
    setState(() => _saving = true);
    await persistLayoutProviderConfig(ref, LayoutProviderConfig(type: _type, baseUrl: _url.text.trim(), apiKey: _key.text.trim()));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('版面识别设置已保存')));
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFF0FDFA), borderRadius: BorderRadius.circular(10)),
    child: const Text('接口协议\nPOST /v1/layout/question-regions\nContent-Type: multipart/form-data，字段 file\n返回：{"provider":"paddle-pp-structure","regions":[{"number":"1","x":0.05,"y":0.08,"width":0.9,"height":0.18,"confidence":0.92}]}\n坐标必须为 0~1 归一化值；结果仅作为可编辑候选框。', style: TextStyle(fontSize: 12)),
  );
}
