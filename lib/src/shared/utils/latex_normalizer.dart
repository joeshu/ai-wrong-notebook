/// 统一 PaddleOCR/MinerU 返回的原始 LaTeX 定界符到 $...$ / $$...$$ 格式。
///
/// 处理：
/// - \(...\) → $...$
/// - \[...\] → $$...$$
/// - \begin{...}...\end{...} 保持原样
/// - 去除 LaTeX 命令前后多余空白
class LatexNormalizer {
  const LatexNormalizer._();

  static String normalize(String input) {
    if (input.isEmpty) return input;
    var result = input;
    // \( ... \) → $ ... $
    result = result.replaceAllMapped(
      RegExp(r'\\\(\s*([\s\S]*?)\s*\\\)'),
      (m) => '\$${m.group(1)}\$',
    );
    // \[ ... \] → $$ ... $$
    result = result.replaceAllMapped(
      RegExp(r'\\\[\s*([\s\S]*?)\s*\\\]'),
      (m) => '\$\$${m.group(1)}\$\$',
    );
    return result;
  }

  /// 判断文本是否包含 LaTeX 公式
  static bool hasFormula(String text) {
    if (text.contains(r'$')) return true;
    if (text.contains(r'\\')) return true;
    // 常见 LaTeX 命令前缀
    if (RegExp(
      r'\\(frac|sqrt|sum|int|begin|alpha|beta|gamma|delta|theta|pi|infty|partial|nabla|cdot|times|pm|mp|leq|geq|neq|approx|equiv|subset|supset|in|notin|forall|exists|rightarrow|leftarrow|Rightarrow|Leftarrow|mapsto)\b',
    ).hasMatch(text)) {
      return true;
    }
    // 数学符号
    if (RegExp(r'[∑√∫≠≤≥≈≡⊆⊇∈∉∀∃→←⇒⇐↦αβγδθπ∞∂∇·×±∓]').hasMatch(text)) {
      return true;
    }
    return false;
  }
}
