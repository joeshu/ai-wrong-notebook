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
  late final TextEditingController _secondaryKey;
  LayoutProviderType _type = LayoutProviderType.currentVision;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() { super.initState(); _url = TextEditingController(); _key = TextEditingController(); _secondaryKey = TextEditingController(); }
  @override
  void dispose() { _url.dispose(); _key.dispose(); _secondaryKey.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (_loaded) return;
    final config = await restoreLayoutProviderConfig(ref);
    if (!mounted) return;
    setState(() { _type = config.type; _url.text = config.baseUrl; _key.text = config.apiKey; _secondaryKey.text = config.secondaryApiKey; _loaded = true; });
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
          value: LayoutProviderType.paddleCloud, groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
          title: const Text('PaddleOCR AI Studio（PP-StructureV3）'),
          subtitle: const Text('云端异步识别；Token 安全存储，不写入备份或日志。'),
        ),
        RadioListTile<LayoutProviderType>(
          value: LayoutProviderType.mineruCloud, groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
          title: const Text('MinerU 精准解析（VLM）'),
          subtitle: const Text('适合公式、多栏和复杂扫描试卷；按题号聚合为候选题框。'),
        ),
        RadioListTile<LayoutProviderType>(
          value: LayoutProviderType.autoCloud, groupValue: _type,
          onChanged: (v) => setState(() => _type = v!),
          title: const Text('自动：PaddleOCR 优先，MinerU 兜底'),
          subtitle: const Text('先走快速识别；题框数量、覆盖率或重叠异常时自动升级 VLM。'),
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
        _ConfigurationStatusCard(type: _type, apiKey: _key.text, secondaryApiKey: _secondaryKey.text, loaded: _loaded),
        if (_type == LayoutProviderType.customHttp || _type == LayoutProviderType.paddleCloud || _type == LayoutProviderType.mineruCloud || _type == LayoutProviderType.autoCloud) ...<Widget>[
          const SizedBox(height: 16),
          if (_type == LayoutProviderType.customHttp)
            TextField(controller: _url, keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: '服务地址', hintText: 'http://nas.local:8000')),
          if (_type == LayoutProviderType.customHttp) const SizedBox(height: 12),
          TextField(controller: _key, obscureText: true,
              decoration: InputDecoration(
                labelText: _type == LayoutProviderType.paddleCloud ? 'AI Studio Token' : _type == LayoutProviderType.mineruCloud ? 'MinerU Token' : _type == LayoutProviderType.autoCloud ? 'PaddleOCR AI Studio Token' : '访问令牌（可选）',
                hintText: _type == LayoutProviderType.paddleCloud ? 'PaddleOCR AI Studio Token 将安全存储' : _type == LayoutProviderType.mineruCloud ? '在 MinerU API 管理页面创建的 Token 将安全存储' : _type == LayoutProviderType.autoCloud ? '快速优先服务的 Token，将安全存储' : 'Bearer Token 将安全存储',
              )),
          if (_type == LayoutProviderType.autoCloud) ...<Widget>[
            const SizedBox(height: 12),
            TextField(controller: _secondaryKey, obscureText: true,
              decoration: const InputDecoration(labelText: 'MinerU Token', hintText: '兜底 VLM 服务的 Token，将安全存储')),
          ],
          const SizedBox(height: 12),
          if (_type == LayoutProviderType.customHttp) const _ProtocolCard()
          else if (_type == LayoutProviderType.paddleCloud) const _PaddleCloudCard()
          else if (_type == LayoutProviderType.mineruCloud) const _MineruCloudCard()
          else const _AutoCloudCard(),
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
    if ((_type == LayoutProviderType.paddleCloud || _type == LayoutProviderType.mineruCloud) && _key.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_type == LayoutProviderType.mineruCloud ? '请填写 MinerU Token' : '请填写 PaddleOCR AI Studio Token')));
      return;
    }
    if (_type == LayoutProviderType.autoCloud && (_key.text.trim().isEmpty || _secondaryKey.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自动策略需要同时填写 PaddleOCR 与 MinerU Token')));
      return;
    }
    setState(() => _saving = true);
    await persistLayoutProviderConfig(ref, LayoutProviderConfig(type: _type, baseUrl: _url.text.trim(), apiKey: _key.text.trim(), secondaryApiKey: _secondaryKey.text.trim()));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('版面识别设置已保存')));
  }
}

class _MineruCloudCard extends StatelessWidget {
  const _MineruCloudCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '服务：MinerU 精准解析 API（VLM）\n应用会申请临时上传地址、上传当前整页图片并轮询解析任务，然后从结果 ZIP 的版面块按题号聚合候选题框。Token 仅使用系统安全存储；整页会上传至 MinerU。候选框必须由你确认后才会裁切入库。',
  );
}

class _PaddleCloudCard extends StatelessWidget {
  const _PaddleCloudCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '服务：PaddleOCR AI Studio · PP-StructureV3\n应用会上传当前整页图片并轮询异步任务；仅将候选框保留在本地。Token 使用系统安全存储，不会写入导出文件、备份或诊断日志。识别结果仍须人工确认后才能裁切入库。',
  );
}

class _AutoCloudCard extends StatelessWidget {
  const _AutoCloudCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '自动策略：先调用 PaddleOCR；仅当候选框少于 2 个、覆盖率异常或候选框严重重叠时，才自动升级 MinerU VLM。两个服务的 Token 分别安全存储；任一候选结果都必须人工确认。',
  );
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '接口协议\nPOST /v1/layout/question-regions\nContent-Type: multipart/form-data，字段 file\n返回：{"provider":"paddle-pp-structure","regions":[{"number":"1","x":0.05,"y":0.08,"width":0.9,"height":0.18,"confidence":0.92}]}\n坐标必须为 0~1 归一化值；结果仅作为可编辑候选框。',
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFF0FDFA), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: const TextStyle(fontSize: 12)),
  );
}


class _ConfigurationStatusCard extends StatelessWidget {
  const _ConfigurationStatusCard({required this.type, required this.apiKey, required this.secondaryApiKey, required this.loaded});
  final LayoutProviderType type;
  final String apiKey;
  final String secondaryApiKey;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final ready = type == LayoutProviderType.currentVision ||
        type == LayoutProviderType.manualOnly ||
        (type == LayoutProviderType.customHttp) ||
        (type == LayoutProviderType.paddleCloud && apiKey.trim().isNotEmpty) ||
        (type == LayoutProviderType.mineruCloud && apiKey.trim().isNotEmpty) ||
        (type == LayoutProviderType.autoCloud && apiKey.trim().isNotEmpty && secondaryApiKey.trim().isNotEmpty);
    final text = !loaded
        ? '正在读取已保存的配置…'
        : ready
            ? '配置可用：导入整页试卷后，在“整页框选切题”页面点击识别即可看到实际服务名称和耗时。'
            : '配置不完整：已选择服务，但安全存储中未读到所需 Token。请重新填写并保存。';
    final color = ready ? const Color(0xFF166534) : const Color(0xFFB45309);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: .3))),
      child: Row(children: <Widget>[
        Icon(ready ? CupertinoIcons.checkmark_shield : CupertinoIcons.exclamationmark_triangle, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
      ]),
    );
  }
}
